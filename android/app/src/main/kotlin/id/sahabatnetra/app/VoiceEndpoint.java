package id.sahabatnetra.app;

/** Energy-based endpoint detector for 16 kHz PCM. This is not a speech classifier. */
public final class VoiceEndpoint {
    private static final int RATE = 16000;
    private int elapsed, consecutiveVoice, voiced, firstVoice = -1, lastVoice;
    private double noise = .002;
    private boolean started;

    public boolean accept(double rms, int count) {
        elapsed += count;
        double threshold = Math.max(started ? .004 : .006, noise * (started ? 2 : 3));
        if (rms >= threshold) {
            if (consecutiveVoice == 0 && !started) firstVoice = elapsed - count;
            consecutiveVoice += count;
            if (started) { voiced += count; lastVoice = elapsed; }
            else if (consecutiveVoice >= RATE * .08) {
                started = true; voiced = consecutiveVoice; lastVoice = elapsed;
            }
        } else {
            consecutiveVoice = 0;
            if (!started) noise = .96 * noise + .04 * rms;
        }
        return elapsed >= RATE * 30 || (!started && elapsed >= RATE * 8)
            || (started && elapsed - lastVoice >= RATE * 1.1);
    }

    public boolean hasSpeech() { return started && voiced >= RATE * .16; }
    public int startSample() { return Math.max(0, firstVoice - RATE / 5); }
    public int endSample() { return Math.min(elapsed, lastVoice + RATE / 5); }
}
