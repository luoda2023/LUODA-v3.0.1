# -*- coding: utf-8 -*-
import io

p = r"src/server/connection.rs"
s = io.open(p, encoding="utf-8").read()

old = """                Some(message::Union::AudioFrame(frame)) => {
                    if !self.disable_audio {
                        if let Some(sender) = &self.audio_sender {
                            allow_err!(sender.send(MediaData::AudioFrame(Box::new(frame))));
                        } else {
                            log::warn!(
                                \"Processing audio frame without the voice call audio sender.\"
                            );
                        }
                    }
                }"""

new = """                Some(message::Union::AudioFrame(frame)) => {
                    if !self.disable_audio {
                        // Mobile (Android/iOS): the Rust Opus decoder is a stub and there is
                        // no cpal output device, so incoming voice-call audio (Opus bytes from
                        // the caller's Dart encoder) is pushed straight to the in-process
                        // Flutter UI, which decodes with opus_dart and plays it. The caller
                        // never sends Misc::AudioFormat, so `audio_sender` stays None and the
                        // bytes would otherwise be dropped here (no audible sound at all).
                        #[cfg(any(target_os = \"android\", target_os = \"ios\"))]
                        if self.voice_calling {
                            use hbb_common::base64::{engine::general_purpose::STANDARD, Engine as _};
                            let b64 = STANDARD.encode(&frame.data);
                            let event = serde_json::json!({
                                \"name\": \"voice_call_audio_frame\",
                                \"data\": b64,
                            })
                            .to_string();
                            crate::flutter::push_global_event(
                                crate::flutter::APP_TYPE_MAIN,
                                event,
                            );
                        } else if let Some(sender) = &self.audio_sender {
                            allow_err!(sender.send(MediaData::AudioFrame(Box::new(frame))));
                        } else {
                            log::warn!(
                                \"Processing audio frame without the voice call audio sender.\"
                            );
                        }
                        #[cfg(not(any(target_os = \"android\", target_os = \"ios\")))]
                        {
                            if let Some(sender) = &self.audio_sender {
                                allow_err!(sender.send(MediaData::AudioFrame(Box::new(frame))));
                            } else {
                                log::warn!(
                                    \"Processing audio frame without the voice call audio sender.\"
                                );
                            }
                        }
                    }
                }"""

assert old in s, "anchor not found"
s = s.replace(old, new, 1)
io.open(p, "w", encoding="utf-8", newline="").write(s)
print("patched OK")
