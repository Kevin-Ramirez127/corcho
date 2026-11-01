use std::sync::{Arc, Mutex, OnceLock};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

#[derive(Clone, Copy)]
struct Synth {
    active: bool,
    gain: f32,
    target_gain: f32,
    volume: f32,
    tone_freq: f32,
    tone_mix: f32,
    phase: f32,
    noise: u32,
}

impl Default for Synth {
    fn default() -> Self {
        Self {
            active: false,
            gain: 0.0,
            target_gain: 0.0,
            volume: 0.35,
            tone_freq: 220.0,
            tone_mix: 0.4,
            phase: 0.0,
            noise: 0x1234_5678,
        }
    }
}

static STATE: OnceLock<Arc<Mutex<Synth>>> = OnceLock::new();
static STREAM: OnceLock<Mutex<Option<cpal::Stream>>> = OnceLock::new();

fn state() -> &'static Arc<Mutex<Synth>> {
    STATE.get_or_init(|| Arc::new(Mutex::new(Synth::default())))
}

fn ensure_stream() -> Result<(), String> {
    let slot = STREAM.get_or_init(|| Mutex::new(None));
    let mut guard = slot.lock().map_err(|_| "audio lock".to_string())?;
    if guard.is_some() {
        return Ok(());
    }
    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .ok_or_else(|| "no audio output device".to_string())?;
    let config = device
        .default_output_config()
        .map_err(|e| e.to_string())?;
    let sample_rate = config.sample_rate().0 as f32;
    let channels = config.channels() as usize;
    let state = state().clone();
    let stream = device
        .build_output_stream(
            &config.into(),
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                let mut s = match state.lock() {
                    Ok(s) => s,
                    Err(_) => return,
                };
                for frame in data.chunks_mut(channels) {
                    // Smooth the on/off transition to avoid clicks.
                    s.gain += (s.target_gain - s.gain) * 0.0008;
                    s.phase += s.tone_freq / sample_rate * std::f32::consts::TAU;
                    if s.phase > std::f32::consts::TAU {
                        s.phase -= std::f32::consts::TAU;
                    }
                    s.noise = s.noise.wrapping_mul(1664525).wrapping_add(1013904223);
                    let white = (s.noise >> 8) as f32 / 16_777_216.0 * 2.0 - 1.0;
                    let tone = s.phase.sin();
                    let mixed = white * (1.0 - s.tone_mix) + tone * s.tone_mix;
                    let sample = mixed * s.volume * s.gain * 0.25;
                    for ch in frame.iter_mut() {
                        *ch = sample;
                    }
                }
            },
            move |err| tracing::warn!("audio stream error: {err}"),
            None,
        )
        .map_err(|e| e.to_string())?;
    stream.play().map_err(|e| e.to_string())?;
    *guard = Some(stream);
    Ok(())
}

pub fn start(volume: f32, tone_freq: f32, tone_mix: f32) -> Result<(), String> {
    {
        let mut s = state().lock().map_err(|_| "audio lock".to_string())?;
        s.active = true;
        s.target_gain = 1.0;
        s.volume = volume.clamp(0.0, 1.0);
        s.tone_freq = tone_freq.clamp(40.0, 4000.0);
        s.tone_mix = tone_mix.clamp(0.0, 1.0);
    }
    ensure_stream()
}

pub fn stop() {
    if let Ok(mut s) = state().lock() {
        s.active = false;
        s.target_gain = 0.0;
    }
}

pub fn update(volume: f32, tone_freq: f32, tone_mix: f32) {
    if let Ok(mut s) = state().lock() {
        s.volume = volume.clamp(0.0, 1.0);
        s.tone_freq = tone_freq.clamp(40.0, 4000.0);
        s.tone_mix = tone_mix.clamp(0.0, 1.0);
    }
}
