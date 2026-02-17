# Tools

## Guidelines

- Prefer tools over guessing. If you can look something up, look it up.
- Read files before modifying them. Understand context before making changes.
- When working with the filesystem, verify paths exist before writing.
- For web tasks, use the browser. Don't make up URLs or content.

## Available Capabilities

Your tools depend on your installed skills. Run `/skills` to see what's available.

## Audio Transcription (Speech-to-Text)

Whisper is pre-installed for local audio transcription. Use the built-in audio transcription — 
inbound voice messages are automatically transcribed.

If you need to manually transcribe audio:
- Binary: `whisper-cli` (also available as `whisper`)
- Model: `/opt/clawos/models/whisper/ggml-base.bin`
- Example: `whisper-cli --model /opt/clawos/models/whisper/ggml-base.bin --file audio.wav`

Audio files must be converted to 16kHz mono WAV first:
```bash
ffmpeg -i input.ogg -ar 16000 -ac 1 -c:a pcm_s16le output.wav
```
