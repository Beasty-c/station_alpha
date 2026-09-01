/**
 * Procedural sound.
 *
 * There are no audio files: every sound is synthesised from noise buffers and
 * oscillators, which keeps the download tiny and the licence simple. The audio
 * context is not created until the player's first gesture, so nothing is ever
 * played before a real interaction — browsers require that, and so does the
 * spec.
 */

type SoundName = 'whoosh' | 'crunch' | 'thud' | 'chime';

export class GameAudio {
  private context: AudioContext | null = null;
  private master: GainNode | null = null;
  private noise: AudioBuffer | null = null;
  private muted = false;
  private failed = false;

  /** Called from a real user gesture. Safe to call repeatedly. */
  unlock(): void {
    if (this.context || this.failed) {
      void this.context?.resume();
      return;
    }
    const Ctor: typeof AudioContext | undefined =
      window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctor) {
      this.failed = true;
      return;
    }
    try {
      const context = new Ctor();
      const master = context.createGain();
      master.gain.value = this.muted ? 0 : 0.5;
      master.connect(context.destination);

      const length = Math.floor(context.sampleRate * 0.6);
      const buffer = context.createBuffer(1, length, context.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1;

      this.context = context;
      this.master = master;
      this.noise = buffer;
      void context.resume();
    } catch {
      // An unavailable audio device must never stop the game.
      this.failed = true;
    }
  }

  setMuted(muted: boolean): void {
    this.muted = muted;
    if (this.master && this.context) {
      this.master.gain.setTargetAtTime(muted ? 0 : 0.5, this.context.currentTime, 0.02);
    }
  }

  play(name: SoundName, intensity = 1): void {
    if (this.muted || !this.context || !this.master || !this.noise) return;
    const context = this.context;
    const now = context.currentTime;
    const strength = Math.max(0.1, Math.min(1, intensity));

    switch (name) {
      case 'whoosh':
        this.playNoise(now, 0.22, 900, 'bandpass', 0.18, (filter) => {
          filter.frequency.setValueAtTime(1400, now);
          filter.frequency.exponentialRampToValueAtTime(280, now + 0.2);
        });
        break;
      case 'crunch': {
        // A few overlapping bursts read as buckling metal.
        for (let i = 0; i < 4; i++) {
          const at = now + i * 0.035 * (1.2 - strength * 0.4);
          this.playNoise(at, 0.13, 2200 - i * 380, 'lowpass', 0.5 * strength);
        }
        this.playTone(now + 0.01, 168, 0.22, 0.16 * strength, 'triangle');
        this.playTone(now + 0.02, 251, 0.18, 0.1 * strength, 'square');
        break;
      }
      case 'thud':
        this.playNoise(now, 0.16, 320, 'lowpass', 0.4);
        this.playTone(now, 92, 0.2, 0.2, 'sine');
        break;
      case 'chime':
        this.playTone(now, 880, 0.5, 0.14, 'sine');
        this.playTone(now + 0.08, 1320, 0.45, 0.1, 'sine');
        this.playTone(now + 0.16, 1760, 0.4, 0.08, 'sine');
        break;
    }
  }

  private playNoise(
    at: number,
    duration: number,
    cutoff: number,
    type: BiquadFilterType,
    gain: number,
    tweak?: (filter: BiquadFilterNode) => void,
  ): void {
    if (!this.context || !this.master || !this.noise) return;
    const source = this.context.createBufferSource();
    source.buffer = this.noise;
    const filter = this.context.createBiquadFilter();
    filter.type = type;
    filter.frequency.value = cutoff;
    filter.Q.value = type === 'bandpass' ? 1.2 : 0.7;
    tweak?.(filter);
    const envelope = this.context.createGain();
    envelope.gain.setValueAtTime(gain, at);
    envelope.gain.exponentialRampToValueAtTime(0.0008, at + duration);
    source.connect(filter).connect(envelope).connect(this.master);
    source.start(at);
    source.stop(at + duration + 0.02);
  }

  private playTone(
    at: number,
    frequency: number,
    duration: number,
    gain: number,
    type: OscillatorType,
  ): void {
    if (!this.context || !this.master) return;
    const oscillator = this.context.createOscillator();
    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, at);
    oscillator.frequency.exponentialRampToValueAtTime(frequency * 0.72, at + duration);
    const envelope = this.context.createGain();
    envelope.gain.setValueAtTime(0.0001, at);
    envelope.gain.exponentialRampToValueAtTime(gain, at + 0.01);
    envelope.gain.exponentialRampToValueAtTime(0.0008, at + duration);
    oscillator.connect(envelope).connect(this.master);
    oscillator.start(at);
    oscillator.stop(at + duration + 0.02);
  }
}
