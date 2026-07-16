#define aom_codec_enc_cfg aom_codec_enc_cfg_forward_hidden
#define aom_codec_dec_cfg aom_codec_dec_cfg_forward_hidden
#include <aom/aom_codec.h>
#include <aom/aom_image.h>
#include <aom/aom_integer.h>
#include <aom/aom_external_partition.h>
#include <aom/aom_frame_buffer.h>
#undef aom_codec_enc_cfg
#undef aom_codec_dec_cfg
#include <aom/aom_encoder.h>
#include <aom/aom_decoder.h>
#include <aom/aomcx.h>
#include <aom/aomdx.h>