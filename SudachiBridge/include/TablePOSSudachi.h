#ifndef TABLEPOS_SUDACHI_H
#define TABLEPOS_SUDACHI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TablePOSSudachiAnalyzer TablePOSSudachiAnalyzer;

TablePOSSudachiAnalyzer *tablepos_sudachi_create(
    const char *config_path,
    const char *resource_dir,
    const char *dictionary_path
);

char *tablepos_sudachi_analyze(
    const TablePOSSudachiAnalyzer *analyzer,
    const char *input
);

void tablepos_sudachi_destroy(TablePOSSudachiAnalyzer *analyzer);
void tablepos_sudachi_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
