#include "CZlib.h"
#include <limits.h>
#include <zlib.h>

size_t maurya_gzip_bound(size_t input_length) {
    if (input_length > UINT_MAX) return 0;
    z_stream stream = {0};
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return 0;
    }
    size_t result = (size_t)deflateBound(&stream, (uLong)input_length);
    deflateEnd(&stream);
    return result;
}

int32_t maurya_gzip_compress(
    const uint8_t *input,
    size_t input_length,
    uint8_t *output,
    size_t *output_length
) {
    if (input_length > UINT_MAX || *output_length > UINT_MAX) return Z_BUF_ERROR;
    z_stream stream = {0};
    int status = deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY);
    if (status != Z_OK) return status;
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_length;
    stream.next_out = output;
    stream.avail_out = (uInt)*output_length;
    status = deflate(&stream, Z_FINISH);
    *output_length = (size_t)stream.total_out;
    deflateEnd(&stream);
    return status == Z_STREAM_END ? Z_OK : status;
}

int32_t maurya_raw_inflate(
    const uint8_t *input,
    size_t input_length,
    uint8_t *output,
    size_t *output_length,
    size_t *consumed_length
) {
    if (input_length > UINT_MAX || *output_length > UINT_MAX) return Z_BUF_ERROR;
    z_stream stream = {0};
    int status = inflateInit2(&stream, -15);
    if (status != Z_OK) return status;
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_length;
    stream.next_out = output;
    stream.avail_out = (uInt)*output_length;
    status = inflate(&stream, Z_FINISH);
    *output_length = (size_t)stream.total_out;
    *consumed_length = (size_t)stream.total_in;
    inflateEnd(&stream);
    return status == Z_STREAM_END ? Z_OK : status;
}

uint32_t maurya_crc32(const uint8_t *bytes, size_t length) {
    if (length > UINT_MAX) return 0;
    return (uint32_t)crc32(0L, bytes, (uInt)length);
}
