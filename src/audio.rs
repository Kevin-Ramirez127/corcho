use std::sync::{Arc, Mutex, OnceLock};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

struct Synth {
    owner: Option<String>,
    active: bool,
    gain: f32,
    target_gain: f32,
    volume: f32,
    tone_freq: f32,
    tone_mix: f32,
    phase: f32,
    noise: u32,
    // Short notification chime mixed into the same output stream as the
    // ambient timbre, so both share one audio device.
    sample_rate: f32,
    chime_frames: u32,
    chime_pos: u32,
    chime_phase: f32,
}

impl Default for Synth {
    fn default() -> Self {
        Self {
            owner: None,
            active: false,
            gain: 0.0,
            target_gain: 0.0,
            volume: 0.35,
            tone_freq: 220.0,
            tone_mix: 0.4,
            phase: 0.0,
            noise: 0x1234_5678,
            sample_rate: 48_000.0,
            chime_frames: 0,
            chime_pos: 0,
            chime_phase: 0.0,
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
    let config = device.default_output_config().map_err(|e| e.to_string())?;
    let sample_rate = config.sample_rate().0 as f32;
    let channels = config.channels() as usize;
    {
        let mut s = state().lock().map_err(|_| "audio lock".to_string())?;
        s.sample_rate = sample_rate;
    }
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
                    let mut sample = mixed * s.volume * s.gain * 0.25;

                    // Three rising notes with a soft decay, about 0.9 s long.
                    if s.chime_frames > 0 {
                        s.chime_frames -= 1;
                        let t = s.chime_pos as f32 / s.sample_rate;
                        let (start, freq) = if t < 0.28 {
                            (0.0, 880.0)
                        } else if t < 0.56 {
                            (0.28, 1046.5)
                        } else {
                            (0.56, 1318.5)
                        };
                        let local = t - start;
                        let env = (1.0 - (local / 0.28)).clamp(0.0, 1.0).powi(2);
                        s.chime_phase += freq / s.sample_rate * std::f32::consts::TAU;
                        if s.chime_phase > std::f32::consts::TAU {
                            s.chime_phase -= std::f32::consts::TAU;
                        }
                        sample += s.chime_phase.sin() * env * 0.35;
                        s.chime_pos += 1;
                    }

                    let sample = sample.clamp(-1.0, 1.0);
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

pub fn start(owner: &str, volume: f32, tone_freq: f32, tone_mix: f32) -> Result<(), String> {
    {
        let mut s = state().lock().map_err(|_| "audio lock".to_string())?;
        s.owner = Some(owner.to_string());
        s.active = true;
        s.target_gain = 1.0;
        s.volume = volume.clamp(0.0, 1.0);
        s.tone_freq = tone_freq.clamp(40.0, 4000.0);
        s.tone_mix = tone_mix.clamp(0.0, 1.0);
    }
    ensure_stream()
}

pub fn stop(owner: &str) {
    if let Ok(mut s) = state().lock() {
        if s.owner.as_deref() == Some(owner) {
            s.active = false;
            s.target_gain = 0.0;
        }
    }
}

/// Play a short three-note chime, used when a Pomodoro phase ends.
pub fn chime() -> Result<(), String> {
    ensure_stream()?;
    let mut s = state().lock().map_err(|_| "audio lock".to_string())?;
    s.chime_pos = 0;
    s.chime_phase = 0.0;
    s.chime_frames = (s.sample_rate * 0.9) as u32;
    Ok(())
}

#[allow(dead_code)]
pub fn update(volume: f32, tone_freq: f32, tone_mix: f32) {
    if let Ok(mut s) = state().lock() {
        s.volume = volume.clamp(0.0, 1.0);
        s.tone_freq = tone_freq.clamp(40.0, 4000.0);
        s.tone_mix = tone_mix.clamp(0.0, 1.0);
    }
}
