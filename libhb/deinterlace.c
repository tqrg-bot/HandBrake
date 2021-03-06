/*
 Copyright (C) 2006 Michael Niedermayer <michaelni@gmx.at>
 
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
*/

#include "hb.h"
#include "ffmpeg/avcodec.h"
#include "mpeg2dec/mpeg2.h"

#define SUPPRESS_AV_LOG

#define YADIF_MODE_DEFAULT     -1
#define YADIF_PARITY_DEFAULT   -1

#define MCDEINT_MODE_DEFAULT   -1
#define MCDEINT_QP_DEFAULT      1

#define ABS(a) ((a) > 0 ? (a) : (-(a)))
#define MIN3(a,b,c) MIN(MIN(a,b),c)
#define MAX3(a,b,c) MAX(MAX(a,b),c)

struct hb_filter_private_s 
{
    int              pix_fmt;
    int              width[3];
    int              height[3];

    int              yadif_mode;
    int              yadif_parity;
    int              yadif_ready;
    
    uint8_t        * yadif_ref[4][3];        
    int              yadif_ref_stride[3];
    
    int              mcdeint_mode;
    int              mcdeint_qp;
    
    int              mcdeint_outbuf_size;
    uint8_t        * mcdeint_outbuf;
    AVCodecContext * mcdeint_avctx_enc;
    AVFrame        * mcdeint_frame;
    AVFrame        * mcdeint_frame_dec;
    
    AVPicture        pic_in;
    AVPicture        pic_out;            
    hb_buffer_t *    buf_out[2];
    hb_buffer_t *    buf_settings;
};

hb_filter_private_t * hb_deinterlace_init( int pix_fmt, 
                                           int width, 
                                           int height,
                                           char * settings );

int hb_deinterlace_work( const hb_buffer_t * buf_in,
                         hb_buffer_t ** buf_out,
                         int pix_fmt,
                         int width, 
                         int height,
                         hb_filter_private_t * pv );

void hb_deinterlace_close( hb_filter_private_t * pv );

hb_filter_object_t hb_filter_deinterlace =
{   
    FILTER_DEINTERLACE,
    "Deinterlace (yadif/mcdeint)",
    NULL,
    hb_deinterlace_init,
    hb_deinterlace_work,
    hb_deinterlace_close,
};

static void yadif_store_ref( const uint8_t ** pic, 
                             hb_filter_private_t * pv )
{
    memcpy( pv->yadif_ref[3], 
            pv->yadif_ref[0], 
            sizeof(uint8_t *)*3 );
    
    memmove( pv->yadif_ref[0], 
             pv->yadif_ref[1], 
             sizeof(uint8_t *)*3*3 );    
    
    int i;
    for( i = 0; i < 3; i++ )
    {
        const uint8_t * src = pic[i];
        uint8_t * ref = pv->yadif_ref[2][i];
        
        int w = pv->width[i];
        int h = pv->height[i];
        int ref_stride = pv->yadif_ref_stride[i];
        
        int y;
        for( y = 0; y < pv->height[i]; y++ )
        {
            memcpy(ref, src, w);
            src = (uint8_t*)src + w;
            ref = (uint8_t*)ref + ref_stride;
        }
    }
}

static void yadif_filter_line( uint8_t *dst,
                               uint8_t *prev,
                               uint8_t *cur, 
                               uint8_t *next,
                               int plane,
                               int parity,
                               hb_filter_private_t * pv )
{
    uint8_t *prev2 = parity ? prev : cur ;
    uint8_t *next2 = parity ? cur  : next;
    
    int w = pv->width[plane];
    int refs = pv->yadif_ref_stride[plane];
    
    int x;
    for( x = 0; x < w; x++)
    {
        int c              = cur[-refs];
        int d              = (prev2[0] + next2[0])>>1;
        int e              = cur[+refs];
        int temporal_diff0 = ABS(prev2[0] - next2[0]);
        int temporal_diff1 = ( ABS(prev[-refs] - c) + ABS(prev[+refs] - e) ) >> 1;
        int temporal_diff2 = ( ABS(next[-refs] - c) + ABS(next[+refs] - e) ) >> 1;
        int diff           = MAX3(temporal_diff0>>1, temporal_diff1, temporal_diff2);
        int spatial_pred   = (c+e)>>1;
        int spatial_score  = ABS(cur[-refs-1] - cur[+refs-1]) + ABS(c-e) +
                             ABS(cur[-refs+1] - cur[+refs+1]) - 1;

#define YADIF_CHECK(j)\
        {   int score = ABS(cur[-refs-1+j] - cur[+refs-1-j])\
                      + ABS(cur[-refs  +j] - cur[+refs  -j])\
                      + ABS(cur[-refs+1+j] - cur[+refs+1-j]);\
            if( score < spatial_score ){\
                spatial_score = score;\
                spatial_pred  = (cur[-refs  +j] + cur[+refs  -j])>>1;\
                            
        YADIF_CHECK(-1) YADIF_CHECK(-2) }} }}
        YADIF_CHECK( 1) YADIF_CHECK( 2) }} }}

        if( pv->yadif_mode < 2 )
        {
            int b = (prev2[-2*refs] + next2[-2*refs])>>1;
            int f = (prev2[+2*refs] + next2[+2*refs])>>1;
            
            int max = MAX3(d-e, d-c, MIN(b-c, f-e));
            int min = MIN3(d-e, d-c, MAX(b-c, f-e));

            diff = MAX3( diff, min, -max );
        }

        if( spatial_pred > d + diff )
        {
            spatial_pred = d + diff;
        }
        else if( spatial_pred < d - diff )
        {
            spatial_pred = d - diff;
        }

        dst[0] = spatial_pred;

        dst++;
        cur++;
        prev++;
        next++;
        prev2++;
        next2++;
    }
}

static void yadif_filter( uint8_t ** dst,
                          int parity,
                          int tff,
                          hb_filter_private_t * pv )
{
    int i;
    for( i = 0; i < 3; i++ )
    {   
        int w = pv->width[i];
        int h = pv->height[i];
        int ref_stride = pv->yadif_ref_stride[i];
        
        int y;
        for( y = 0; y < h; y++ )
        {
            if( (y ^ parity) &  1 )
            {
                uint8_t *prev = &pv->yadif_ref[0][i][y*ref_stride];
                uint8_t *cur  = &pv->yadif_ref[1][i][y*ref_stride];
                uint8_t *next = &pv->yadif_ref[2][i][y*ref_stride];
                uint8_t *dst2 = &dst[i][y*w];
                
                yadif_filter_line( dst2, prev, cur, next, i, parity ^ tff, pv );
            }
            else
            {
                memcpy( &dst[i][y*w], 
                        &pv->yadif_ref[1][i][y*ref_stride], 
                        w * sizeof(uint8_t) );
            }
        }
    }
}

static void mcdeint_filter( uint8_t ** dst, 
                            uint8_t ** src,
                            int parity,
                            hb_filter_private_t * pv )
{
    int x, y, i;
    int out_size;    
   
#ifdef SUPPRESS_AV_LOG
    /* TODO: temporarily change log level to suppress obnoxious debug output */
    int loglevel = av_log_get_level();
    av_log_set_level( AV_LOG_QUIET );
#endif
    
    for( i=0; i<3; i++ )
    {
        pv->mcdeint_frame->data[i] = src[i];
        pv->mcdeint_frame->linesize[i] = pv->width[i];
    }    
    pv->mcdeint_avctx_enc->me_cmp     = FF_CMP_SAD;
    pv->mcdeint_avctx_enc->me_sub_cmp = FF_CMP_SAD;
    pv->mcdeint_frame->quality        = pv->mcdeint_qp * FF_QP2LAMBDA;
    
    out_size = avcodec_encode_video( pv->mcdeint_avctx_enc, 
                                     pv->mcdeint_outbuf, 
                                     pv->mcdeint_outbuf_size, 
                                     pv->mcdeint_frame );
    
    pv->mcdeint_frame_dec = pv->mcdeint_avctx_enc->coded_frame;
    
    for( i = 0; i < 3; i++ )
    {
        int w    = pv->width[i];
        int h    = pv->height[i];
        int fils = pv->mcdeint_frame_dec->linesize[i];
        int srcs = pv->width[i];
        
        for( y = 0; y < h; y++ )
        {
            if( (y ^ parity) & 1 )
            {
                for( x = 0; x < w; x++ )
                {
                    if( (x-2)+(y-1)*w >= 0 && (x+2)+(y+1)*w < w*h )
                    { 
                        uint8_t * filp = 
                            &pv->mcdeint_frame_dec->data[i][x + y*fils];
                        uint8_t * srcp = &src[i][x + y*srcs];

                        int diff0 = filp[-fils] - srcp[-srcs];
                        int diff1 = filp[+fils] - srcp[+srcs];
                        
                        int spatial_score = 
                              ABS(srcp[-srcs-1] - srcp[+srcs-1])
                            + ABS(srcp[-srcs  ] - srcp[+srcs  ])
                            + ABS(srcp[-srcs+1] - srcp[+srcs+1]) - 1;
                        
                        int temp = filp[0];
                        
#define MCDEINT_CHECK(j)\
                        {   int score = ABS(srcp[-srcs-1+j] - srcp[+srcs-1-j])\
                                      + ABS(srcp[-srcs  +j] - srcp[+srcs  -j])\
                                      + ABS(srcp[-srcs+1+j] - srcp[+srcs+1-j]);\
                            if( score < spatial_score ) {\
                                spatial_score = score;\
                                diff0 = filp[-fils+j] - srcp[-srcs+j];\
                                diff1 = filp[+fils-j] - srcp[+srcs-j];
                                        
                        MCDEINT_CHECK(-1) MCDEINT_CHECK(-2) }} }}
                        MCDEINT_CHECK( 1) MCDEINT_CHECK( 2) }} }}

                        if(diff0 + diff1 > 0)
                        {
                            temp -= (diff0 + diff1 - 
                                     ABS( ABS(diff0) - ABS(diff1) ) / 2) / 2;
                        }
                        else
                        {
                            temp -= (diff0 + diff1 + 
                                     ABS( ABS(diff0) - ABS(diff1) ) / 2) / 2;
                        }

                        filp[0] = dst[i][x + y*w] = 
                            temp > 255U ? ~(temp>>31) : temp;
                    }
                    else
                    {
                        dst[i][x + y*w] = 
                            pv->mcdeint_frame_dec->data[i][x + y*fils];
                    }
                }
            }
        }

        for( y = 0; y < h; y++ )
        {
            if( !((y ^ parity) & 1) )
            {
                for( x = 0; x < w; x++ )
                {
                    pv->mcdeint_frame_dec->data[i][x + y*fils] =
                        dst[i][x + y*w]= src[i][x + y*srcs];
                }
            }
        }
    }

#ifdef SUPPRESS_AV_LOG
    /* TODO: restore previous log level */
    av_log_set_level(loglevel);
#endif
}

hb_filter_private_t * hb_deinterlace_init( int pix_fmt, 
                                           int width, 
                                           int height,
                                           char * settings )
{
    if( pix_fmt != PIX_FMT_YUV420P )
    {
        return 0;
    }
    
    hb_filter_private_t * pv = calloc( 1, sizeof(struct hb_filter_private_s) );
    
    pv->pix_fmt = pix_fmt;

    pv->width[0]  = width;
    pv->height[0] = height;    
    pv->width[1]  = pv->width[2]  = width >> 1;
    pv->height[1] = pv->height[2] = height >> 1;    
    
    int buf_size = 3 * width * height / 2;    
    pv->buf_out[0] = hb_buffer_init( buf_size );
    pv->buf_out[1] = hb_buffer_init( buf_size );
    pv->buf_settings = hb_buffer_init( 0 );
    
    pv->yadif_ready    = 0;
    pv->yadif_mode     = YADIF_MODE_DEFAULT;
    pv->yadif_parity   = YADIF_PARITY_DEFAULT;    
    
    pv->mcdeint_mode   = MCDEINT_MODE_DEFAULT;
    pv->mcdeint_qp     = MCDEINT_QP_DEFAULT;
    
    if( settings )
    {
        sscanf( settings, "%d:%d:%d:%d", 
                &pv->yadif_mode, 
                &pv->yadif_parity,
                &pv->mcdeint_mode,
                &pv->mcdeint_qp );
    }
    
    /* Allocate yadif specific buffers */
    if( pv->yadif_mode >= 0 )
    {
        int i, j;
        for( i = 0; i < 3; i++ )
        {   
            int is_chroma = !!i;
            int w = ((width   + 31) & (~31))>>is_chroma;
            int h = ((height+6+ 31) & (~31))>>is_chroma;
            
            pv->yadif_ref_stride[i] = w;
            
            for( j = 0; j < 3; j++ )
            {
                pv->yadif_ref[j][i] = malloc( w*h*sizeof(uint8_t) ) + 3*w;
            }        
        }
    }
    
    /* Allocate mcdeint specific buffers */
    if( pv->mcdeint_mode >= 0 )
    {
		avcodec_init();
        register_avcodec( &snow_encoder );
        
        AVCodec * enc = avcodec_find_encoder( CODEC_ID_SNOW );
        
        int i;
        for (i = 0; i < 3; i++ )
        {
            AVCodecContext * avctx_enc;
            
            avctx_enc = pv->mcdeint_avctx_enc = avcodec_alloc_context();
            
            avctx_enc->width                    = width;
            avctx_enc->height                   = height;
            avctx_enc->time_base                = (AVRational){1,25};  // meaningless
            avctx_enc->gop_size                 = 300;
            avctx_enc->max_b_frames             = 0;
            avctx_enc->pix_fmt                  = PIX_FMT_YUV420P;
            avctx_enc->flags                    = CODEC_FLAG_QSCALE | CODEC_FLAG_LOW_DELAY;
            avctx_enc->strict_std_compliance    = FF_COMPLIANCE_EXPERIMENTAL;
            avctx_enc->global_quality           = 1;
            avctx_enc->flags2                   = CODEC_FLAG2_MEMC_ONLY;
            avctx_enc->me_cmp                   = FF_CMP_SAD; //SSE;
            avctx_enc->me_sub_cmp               = FF_CMP_SAD; //SSE;
            avctx_enc->mb_cmp                   = FF_CMP_SSE;
            
            switch( pv->mcdeint_mode )
            {
                case 3:
                    avctx_enc->refs = 3;
                case 2:
                    avctx_enc->me_method = ME_ITER;
                case 1:
                    avctx_enc->flags |= CODEC_FLAG_4MV;
                    avctx_enc->dia_size =2;
                case 0:
                    avctx_enc->flags |= CODEC_FLAG_QPEL;
            }
            
            avcodec_open(avctx_enc, enc);        
        }
        
        pv->mcdeint_frame       = avcodec_alloc_frame();
        pv->mcdeint_outbuf_size = width * height * 10;
        pv->mcdeint_outbuf      = malloc( pv->mcdeint_outbuf_size );
    }

    return pv;
}

void hb_deinterlace_close( hb_filter_private_t * pv )
{
    if( !pv ) 
    {
        return;
    }
    
    /* Cleanup frame buffers */
    if( pv->buf_out[0] )
    {
        hb_buffer_close( &pv->buf_out[0] );
    }    
    if( pv->buf_out[1] )
    {
        hb_buffer_close( &pv->buf_out[1] );
    }
    if (pv->buf_settings )
    {
        hb_buffer_close( &pv->buf_settings );
    }

    /* Cleanup yadif specific buffers */
    if( pv->yadif_mode >= 0 )
    {
        int i;
        for( i = 0; i<3*3; i++ )
        {
            uint8_t **p = &pv->yadif_ref[i%3][i/3];
            if (*p) 
            {
                free( *p - 3*pv->yadif_ref_stride[i/3] );
                *p = NULL;
            }
        }
    }
    
    /* Cleanup mcdeint specific buffers */
    if( pv->mcdeint_mode >= 0 )
    {
        if( pv->mcdeint_avctx_enc )
        {
            avcodec_close( pv->mcdeint_avctx_enc );
            av_freep( &pv->mcdeint_avctx_enc );
        }        
        if( pv->mcdeint_outbuf )
        {
            free( pv->mcdeint_outbuf );
        }        
    }    
    
    free( pv );
}

int hb_deinterlace_work( const hb_buffer_t * buf_in,
                         hb_buffer_t ** buf_out,
                         int pix_fmt,
                         int width, 
                         int height,
                         hb_filter_private_t * pv )
{
    if( !pv || 
        pix_fmt != pv->pix_fmt ||
        width   != pv->width[0] ||
        height  != pv->height[0] )
    {
        return FILTER_FAILED;
    }
    
    avpicture_fill( &pv->pic_in, buf_in->data, 
                    pix_fmt, width, height );

    /* Use libavcodec deinterlace if yadif_mode < 0 */
    if( pv->yadif_mode < 0 )
    {        
        avpicture_fill( &pv->pic_out, pv->buf_out[0]->data, 
                        pix_fmt, width, height );
        
        avpicture_deinterlace( &pv->pic_out, &pv->pic_in, 
                               pix_fmt, width, height );
        
        hb_buffer_copy_settings( pv->buf_out[0], buf_in );

        *buf_out = pv->buf_out[0];
        
        return FILTER_OK;
    }
    
    /* Determine if top-field first layout */
    int tff;
    if( pv->yadif_parity < 0 )
    {
        tff = !!(buf_in->flags & PIC_FLAG_TOP_FIELD_FIRST);
    }
    else
    {
        tff = (pv->yadif_parity & 1) ^ 1;
    }
    
    /* Store current frame in yadif cache */
    yadif_store_ref( (const uint8_t**)pv->pic_in.data, pv );
    
    /* If yadif is not ready, store another ref and return FILTER_DELAY */
    if( pv->yadif_ready == 0 )
    {
        yadif_store_ref( (const uint8_t**)pv->pic_in.data, pv );
        
        hb_buffer_copy_settings( pv->buf_settings, buf_in );

        pv->yadif_ready = 1;
        
        return FILTER_DELAY;
    }

    /* Perform yadif and mcdeint filtering */
    int frame;
    for( frame = 0; frame <= (pv->yadif_mode & 1); frame++ )
    {
        int parity = frame ^ tff ^ 1;
        
        avpicture_fill( &pv->pic_out, pv->buf_out[!(frame^1)]->data, 
                        pix_fmt, width, height );
        
        yadif_filter( pv->pic_out.data, parity, tff, pv );

        if( pv->mcdeint_mode >= 0 )
        {
            avpicture_fill( &pv->pic_in,  pv->buf_out[(frame^1)]->data, 
                            pix_fmt, width, height );
            
            mcdeint_filter( pv->pic_in.data, pv->pic_out.data, parity, pv );
            
            *buf_out = pv->buf_out[ (frame^1)];
        }
        else
        {
            *buf_out = pv->buf_out[!(frame^1)];
        }
    }
    
    /* Copy buffered settings to output buffer settings */
    hb_buffer_copy_settings( *buf_out, pv->buf_settings );
    
    /* Replace buffered settings with input buffer settings */
    hb_buffer_copy_settings( pv->buf_settings, buf_in );    

    return FILTER_OK;
}


