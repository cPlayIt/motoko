/*
 * Copyright (c) 2017 Christian Hansen <chansen@cpan.org>
 * <https://github.com/chansen/c-utf8-valid>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#define UTF8_VALID_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "rts.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 *    UTF-8 Encoding Form
 *
 *    U+0000..U+007F       0xxxxxxx
 *    U+0080..U+07FF       110xxxxx 10xxxxxx
 *    U+0800..U+FFFF       1110xxxx 10xxxxxx 10xxxxxx
 *   U+10000..U+10FFFF     11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
 *
 *
 *    U+0000..U+007F       00..7F
 *                      N  C0..C1  80..BF                   1100000x 10xxxxxx
 *    U+0080..U+07FF       C2..DF  80..BF
 *                      N  E0      80..9F  80..BF           11100000 100xxxxx
 *    U+0800..U+0FFF       E0      A0..BF  80..BF
 *    U+1000..U+CFFF       E1..EC  80..BF  80..BF
 *    U+D000..U+D7FF       ED      80..9F  80..BF
 *                      S  ED      A0..BF  80..BF           11101101 101xxxxx
 *    U+E000..U+FFFF       EE..EF  80..BF  80..BF
 *                      N  F0      80..8F  80..BF  80..BF   11110000 1000xxxx
 *   U+10000..U+3FFFF      F0      90..BF  80..BF  80..BF
 *   U+40000..U+FFFFF      F1..F3  80..BF  80..BF  80..BF
 *  U+100000..U+10FFFF     F4      80..8F  80..BF  80..BF   11110100 1000xxxx
 *
 *  Legend:
 *    N = Non-shortest form
 *    S = Surrogates
 */

bool
utf8_check(const char *src, size_t len, size_t *cursor) {
  const unsigned char *cur = (const unsigned char *)src;
  const unsigned char *end = cur + len;
  const unsigned char *p;
  unsigned char buf[4];
  uint32_t v;

  while (true) {
    if (cur >= end - 3) {
      if (cur == end)
        break;
      buf[0] = buf[1] = buf[2] = buf[3] = 0;
      as_memcpy((char *)buf, (const char *)cur, end - cur);
      p = (const unsigned char *)buf;
    } else {
      p = cur;
    }

    v = p[0];
    /* 0xxxxxxx */
    if ((v & 0x80) == 0) {
      cur += 1;
      continue;
    }

    v = (v << 8) | p[1];
    /* 110xxxxx 10xxxxxx */
    if ((v & 0xE0C0) == 0xC080) {
      /* Ensure that the top 4 bits is not zero */
      v = v & 0x1E00;
      if (v == 0)
        break;
      cur += 2;
      continue;
    }

    v = (v << 8) | p[2];
    /* 1110xxxx 10xxxxxx 10xxxxxx */
    if ((v & 0xF0C0C0) == 0xE08080) {
      /* Ensure that the top 5 bits is not zero and not a surrogate */
      v = v & 0x0F2000;
      if (v == 0 || v == 0x0D2000)
        break;
      cur += 3;
      continue;
    }

    v = (v << 8) | p[3];
    /* 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx */
    if ((v & 0xF8C0C0C0) == 0xF0808080) {
      /* Ensure that the top 5 bits is not zero and not out of range */
      v = v & 0x07300000;
      if (v == 0 || v > 0x04000000)
        break;
      cur += 4;
      continue;
    }

    break;
  }

  if (cursor)
    *cursor = (const char *)cur - src;

  return cur == end;
}

bool
utf8_valid(const char *src, size_t len) {
  return utf8_check(src, len, NULL);
}


export void utf8_validate(const char *src, size_t len) {
  if (utf8_valid(src, len))
    return;
  idl_trap_with("UTF-8 validation failure");
}
