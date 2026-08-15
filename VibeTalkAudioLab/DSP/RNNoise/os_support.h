/* Copyright (c) 2011 Xiph.Org Foundation
   Written by Jean-Marc Valin */
/*
   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

   - Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/* This is a placeholder file that provides basic OS support
   functionality (malloc/free/memcpy wrappers) for platforms that
   do not provide a custom implementation via CUSTOM_SUPPORT. */

#ifndef OS_SUPPORT_H
#define OS_SUPPORT_H

#include <stdlib.h>
#include <string.h>

#include "arch.h"

#ifdef CUSTOM_SUPPORT
#include "custom_support.h"
#endif

#ifndef OVERRIDE_OPUS_ALLOC
static OPUS_INLINE void *opus_alloc (size_t size)
{
   return malloc(size);
}
#endif

#ifndef OVERRIDE_OPUS_ALLOC_SCRATCH
static OPUS_INLINE void *opus_alloc_scratch (size_t size)
{
   /* Scratch space doesn't need to be cleared, so let's skip the memset */
   return malloc(size);
}
#endif

#ifndef OVERRIDE_OPUS_FREE
static OPUS_INLINE void opus_free (void *ptr)
{
    free(ptr);
}
#endif

#ifndef OVERRIDE_OPUS_COPY
/** Copy n elements from src to dst. The 0* term provides compile-time type checking  */
#define OPUS_COPY(dst, src, n) (memcpy((dst), (src), (n)*sizeof(*(dst)) + 0*((dst)-(src)) ))
#endif

#ifndef OVERRIDE_OPUS_MOVE
/** Copy n elements from src to dst, allowing overlapping regions. The 0* term
    provides compile-time type checking */
#define OPUS_MOVE(dst, src, n) (memmove((dst), (src), (n)*sizeof(*(dst)) + 0*((dst)-(src)) ))
#endif

#ifndef OVERRIDE_OPUS_CLEAR
/** Set n elements of dst to zero */
#define OPUS_CLEAR(dst, n) (memset((dst), 0, (n)*sizeof(*(dst))))
#endif

#endif /* OS_SUPPORT_H */
