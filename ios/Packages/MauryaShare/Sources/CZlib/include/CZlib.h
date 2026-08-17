#ifndef MAURYA_CZLIB_H
#define MAURYA_CZLIB_H

#include <stddef.h>
#include <stdint.h>

size_t maurya_gzip_bound(size_t input_length);
int32_t maurya_gzip_compress(
    const uint8_t *input,
    size_t input_length,
    uint8_t *output,
    size_t *output_length
);
int32_t maurya_raw_inflate(
    const uint8_t *input,
    size_t input_length,
    uint8_t *output,
    size_t *output_length,
    size_t *consumed_length
);
uint32_t maurya_crc32(const uint8_t *bytes, size_t length);

#endif
