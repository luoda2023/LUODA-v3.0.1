// Android opus stub implementation
// This is a minimal stub for Android builds to avoid the system opus dependency

#[cfg(any(target_os = "android", target_os = "ios"))]
pub mod android_opus_stub {
    use std::fmt;

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Channels {
        Mono = 1,
        Stereo = 2,
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Application {
        Voip,
        Audio,
        LowDelay,
    }

    pub struct Decoder {
        channels: Channels,
        sample_rate: u32,
    }

    pub struct Encoder {
        channels: Channels,
        sample_rate: u32,
        application: Application,
    }

    #[derive(Debug)]
    pub enum Error {
        InvalidArgument,
        InvalidState,
        InternalError,
        Unimplemented,
        InvalidPacket,
        AllocFail,
        BadArg,
        BufferTooSmall,
        InvalidSampleRate,
        InvalidChannels,
    }

    impl fmt::Display for Error {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            match self {
                Error::InvalidArgument => write!(f, "Invalid argument"),
                Error::InvalidState => write!(f, "Invalid state"),
                Error::InternalError => write!(f, "Internal error"),
                Error::Unimplemented => write!(f, "Unimplemented"),
                Error::InvalidPacket => write!(f, "Invalid packet"),
                Error::AllocFail => write!(f, "Allocation failed"),
                Error::BadArg => write!(f, "Bad argument"),
                Error::BufferTooSmall => write!(f, "Buffer too small"),
                Error::InvalidSampleRate => write!(f, "Invalid sample rate"),
                Error::InvalidChannels => write!(f, "Invalid channels"),
            }
        }
    }

    impl std::error::Error for Error {}

    pub type Result<T> = std::result::Result<T, Error>;

    impl Decoder {
        pub fn new(sample_rate: u32, channels: Channels) -> Result<Self> {
            Ok(Decoder {
                channels,
                sample_rate,
            })
        }

        pub fn decode(&mut self, data: &[u8], output: &mut [i16], _decode_fec: bool) -> Result<usize> {
            // Return silence for Android stub
            if output.len() >= 960 * self.channels as usize {
                let samples = 960;
                for i in 0..samples * self.channels as usize {
                    output[i] = 0;
                }
                Ok(samples)
            } else {
                Err(Error::BufferTooSmall)
            }
        }

        pub fn decode_float(&mut self, _data: &[u8], _output: &mut [f32], _decode_fec: bool) -> Result<usize> {
            Err(Error::Unimplemented)
        }
    }

    impl Encoder {
        pub fn new(sample_rate: u32, channels: Channels, application: Application) -> Result<Self> {
            Ok(Encoder {
                channels,
                sample_rate,
                application,
            })
        }

        pub fn encode(&mut self, input: &[i16], output: &mut [u8]) -> Result<usize> {
            // Return empty packet for Android stub
            if output.len() >= 2 {
                output[0] = 0xF8; // Simple opus packet header
                output[1] = 0xFF; // Terminator
                Ok(2)
            } else {
                Err(Error::BufferTooSmall)
            }
        }

        pub fn encode_float(&mut self, _input: &[f32], _output: &mut [u8]) -> Result<usize> {
            Err(Error::Unimplemented)
        }

 pub fn encode_vec_float(&mut self, input: &[f32], _max_size: usize) -> Result<Vec<u8>> {
 // On Android/iOS, we don't have a real Opus encoder in Rust.
 // Return raw PCM f32 bytes prefixed with a magic marker so the
 // Dart-side decoder can detect "raw PCM mode" and play directly
 // without Opus decoding.
 let mut output = Vec::with_capacity(4 + input.len() * 4);
 output.extend_from_slice(&[0x52, 0x41, 0x57, 0x31]); // "RAW1" magic
 let mut bytes = vec![0u8; input.len() * 4];
 bytes.copy_from_slice(unsafe {
 std::slice::from_raw_parts(input.as_ptr() as *const u8, input.len() * 4)
 });
 output.extend_from_slice(&bytes);
 Ok(output)
 }

        pub fn set_bitrate(&mut self, _bitrate: i32) -> Result<()> {
            Ok(())
        }

        pub fn set_complexity(&mut self, _complexity: i32) -> Result<()> {
            Ok(())
        }

        pub fn set_signal(&mut self, _signal: i32) -> Result<()> {
            Ok(())
        }
    }
}

// Re-export our stub implementation for Android and iOS
#[cfg(any(target_os = "android", target_os = "ios"))]
pub use android_opus_stub::*;

// For non-mobile platforms, use the real magnum-opus
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub use magnum_opus::*;
