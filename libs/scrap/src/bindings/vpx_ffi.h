// Hide the forward declarations of vpx_codec_enc_cfg / vpx_codec_dec_cfg that appear in
// vpx_codec.h's union fields.  Without this, bindgen emits an opaque placeholder struct
// for both names and never picks up the complete typedefs in vpx_encoder.h / vpx_decoder.h.
// The Rust binding then lacks the real fields, breaking the encoder/decoder setup code.
// We post-process the generated binding in build.rs to turn the placeholder into a type
// alias of the real struct so the union field uses the complete definition.
#define vpx_codec_enc_cfg vpx_codec_enc_cfg_forward_hidden
#define vpx_codec_dec_cfg vpx_codec_dec_cfg_forward_hidden
#include <vpx/vpx_codec.h>
#undef vpx_codec_enc_cfg
#undef vpx_codec_dec_cfg
#include <vpx/vpx_encoder.h>
#include <vpx/vpx_decoder.h>
#include <vpx/vp8.h>
#include <vpx/vp8cx.h>
#include <vpx/vp8dx.h>
#include <vpx/vpx_frame_buffer.h>
#include <vpx/vpx_image.h>
#include <vpx/vpx_integer.h>
