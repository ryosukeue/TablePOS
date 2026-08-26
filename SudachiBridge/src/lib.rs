use serde::Serialize;
use std::collections::HashSet;
use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;
use std::ptr;
use std::sync::Arc;
use sudachi::analysis::stateless_tokenizer::StatelessTokenizer;
use sudachi::analysis::{Mode, Tokenize};
use sudachi::config::Config;
use sudachi::dic::dictionary::JapaneseDictionary;

pub struct Analyzer {
    tokenizer: StatelessTokenizer<Arc<JapaneseDictionary>>,
}

#[derive(Serialize)]
struct AnalysisResponse {
    normalized: String,
    reading: String,
    tokens: Vec<String>,
    error: Option<String>,
}

#[no_mangle]
pub unsafe extern "C" fn tablepos_sudachi_create(
    config_path: *const c_char,
    resource_dir: *const c_char,
    dictionary_path: *const c_char,
) -> *mut Analyzer {
    let Some(config_path) = c_path(config_path) else {
        return ptr::null_mut();
    };
    let Some(resource_dir) = c_path(resource_dir) else {
        return ptr::null_mut();
    };
    let Some(dictionary_path) = c_path(dictionary_path) else {
        return ptr::null_mut();
    };

    let config = match Config::new(Some(config_path), Some(resource_dir), Some(dictionary_path)) {
        Ok(config) => config,
        Err(_) => return ptr::null_mut(),
    };
    let dictionary = match JapaneseDictionary::from_cfg(&config) {
        Ok(dictionary) => dictionary,
        Err(_) => return ptr::null_mut(),
    };
    let analyzer = Analyzer {
        tokenizer: StatelessTokenizer::new(Arc::new(dictionary)),
    };
    Box::into_raw(Box::new(analyzer))
}

#[no_mangle]
pub unsafe extern "C" fn tablepos_sudachi_analyze(
    analyzer: *const Analyzer,
    input: *const c_char,
) -> *mut c_char {
    if analyzer.is_null() || input.is_null() {
        return response_string(AnalysisResponse::failure("invalid analyzer or input"));
    }
    let analyzer = &*analyzer;
    let input = match CStr::from_ptr(input).to_str() {
        Ok(input) => input,
        Err(_) => return response_string(AnalysisResponse::failure("input is not UTF-8")),
    };

    response_string(analyzer.analyze(input))
}

impl Analyzer {
    fn analyze(&self, input: &str) -> AnalysisResponse {
        let c_morphemes = match self.tokenizer.tokenize(input, Mode::C, false) {
            Ok(morphemes) => morphemes,
            Err(error) => return AnalysisResponse::failure(error.to_string()),
        };

        let mut normalized = String::new();
        let mut reading = String::new();
        let mut tokens = Vec::new();
        let mut seen = HashSet::new();

        for morpheme in c_morphemes.iter() {
            let surface = morpheme.surface().to_string();
            let normalized_form = fallback_owned(morpheme.normalized_form(), &surface);
            let reading_form = fallback_owned(morpheme.reading_form(), &surface);
            normalized.push_str(&normalized_form);
            reading.push_str(&reading_form);
            add_unique(&mut tokens, &mut seen, surface);
            add_unique(&mut tokens, &mut seen, normalized_form);
            add_unique(&mut tokens, &mut seen, reading_form);
        }

        for mode in [Mode::A, Mode::B] {
            match self.tokenizer.tokenize(input, mode, false) {
                Ok(morphemes) => {
                    for morpheme in morphemes.iter() {
                        let surface = morpheme.surface().to_string();
                        let normalized_form = fallback_owned(morpheme.normalized_form(), &surface);
                        let reading_form = fallback_owned(morpheme.reading_form(), &surface);
                        add_unique(&mut tokens, &mut seen, surface);
                        add_unique(&mut tokens, &mut seen, normalized_form);
                        add_unique(&mut tokens, &mut seen, reading_form);
                    }
                }
                Err(error) => return AnalysisResponse::failure(error.to_string()),
            }
        }

        AnalysisResponse {
            normalized,
            reading,
            tokens,
            error: None,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn tablepos_sudachi_destroy(analyzer: *mut Analyzer) {
    if !analyzer.is_null() {
        drop(Box::from_raw(analyzer));
    }
}

#[no_mangle]
pub unsafe extern "C" fn tablepos_sudachi_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

impl AnalysisResponse {
    fn failure(error: impl Into<String>) -> Self {
        Self {
            normalized: String::new(),
            reading: String::new(),
            tokens: Vec::new(),
            error: Some(error.into()),
        }
    }
}

fn fallback_owned(value: &str, surface: &str) -> String {
    if value.is_empty() {
        surface.to_owned()
    } else {
        value.to_owned()
    }
}

fn add_unique(tokens: &mut Vec<String>, seen: &mut HashSet<String>, token: String) {
    if !token.is_empty() && seen.insert(token.clone()) {
        tokens.push(token);
    }
}

fn response_string(response: AnalysisResponse) -> *mut c_char {
    let json = serde_json::to_string(&response).unwrap_or_else(|_| {
        r#"{"normalized":"","reading":"","tokens":[],"error":"serialization failed"}"#.to_owned()
    });
    CString::new(json.replace('\0', "")).unwrap().into_raw()
}

unsafe fn c_path(value: *const c_char) -> Option<PathBuf> {
    if value.is_null() {
        return None;
    }
    CStr::from_ptr(value).to_str().ok().map(PathBuf::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_analyzer() -> Analyzer {
        let resources = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../TablePOS/Resources/SudachiResources.bundle");
        let config = Config::new(
            Some(resources.join("sudachi.json")),
            Some(resources.clone()),
            Some(resources.join("system.dic")),
        )
        .expect("configuration should load");
        let dictionary = JapaneseDictionary::from_cfg(&config).expect("dictionary should load");
        Analyzer {
            tokenizer: StatelessTokenizer::new(Arc::new(dictionary)),
        }
    }

    #[test]
    fn produces_japanese_readings_and_normalized_forms() {
        let analyzer = test_analyzer();
        let rice_ball = analyzer.analyze("塩むすび");
        assert_eq!(rice_ball.reading, "シオムスビ");
        assert!(
            rice_ball.tokens.iter().any(|token| token == "塩結び"),
            "unexpected tokens: {:?}",
            rice_ball.tokens
        );

        let beer = analyzer.analyze("生ビール");
        assert_eq!(beer.reading, "ナマビール");

        let variant = analyzer.analyze("呑み");
        assert_eq!(variant.normalized, "飲む");
    }

    #[test]
    fn c_abi_loads_resources_and_returns_json() {
        let resources = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../TablePOS/Resources/SudachiResources.bundle");
        let config = CString::new(resources.join("sudachi.json").to_string_lossy().as_bytes())
            .expect("config path should not contain nulls");
        let resource_dir = CString::new(resources.to_string_lossy().as_bytes())
            .expect("resource path should not contain nulls");
        let dictionary = CString::new(resources.join("system.dic").to_string_lossy().as_bytes())
            .expect("dictionary path should not contain nulls");
        let input = CString::new("生ビール").unwrap();

        unsafe {
            let analyzer = tablepos_sudachi_create(
                config.as_ptr(),
                resource_dir.as_ptr(),
                dictionary.as_ptr(),
            );
            assert!(!analyzer.is_null());
            let response = tablepos_sudachi_analyze(analyzer, input.as_ptr());
            assert!(!response.is_null());
            let json = CStr::from_ptr(response).to_string_lossy().into_owned();
            let value: serde_json::Value = serde_json::from_str(&json).unwrap();
            assert_eq!(value["reading"], "ナマビール");
            assert!(value["error"].is_null());
            tablepos_sudachi_string_free(response);
            tablepos_sudachi_destroy(analyzer);
        }
    }
}
