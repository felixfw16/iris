import id.sahabatnetra.app.VoiceEndpoint;

public final class VoiceEndpointCheck {
    private static boolean feed(VoiceEndpoint detector, double rms, int frames) {
        boolean done = false;
        for (int i = 0; i < frames; i++) done = detector.accept(rms, 320);
        return done;
    }
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        VoiceEndpoint shortSpeech = new VoiceEndpoint();
        feed(shortSpeech, .001, 20);
        check(!feed(shortSpeech, .03, 30), "speech must continue");
        check(!feed(shortSpeech, .001, 30), "short pause must not end speech");
        check(feed(shortSpeech, .001, 26), "silence must end speech");
        check(shortSpeech.hasSpeech(), "short utterance accepted");
        check(shortSpeech.startSample() < 6400, "pre-roll preserves onset");
        VoiceEndpoint longSpeech = new VoiceEndpoint();
        check(!feed(longSpeech, .025, 500), "10-second speech must not be cut at four seconds");
        check(feed(longSpeech, .001, 56), "long utterance ends on silence");
        VoiceEndpoint silent = new VoiceEndpoint();
        check(feed(silent, .001, 400) && !silent.hasSpeech(), "silence times out without transcription");
        VoiceEndpoint click = new VoiceEndpoint();
        feed(click, .5, 1);
        check(feed(click, .001, 400) && !click.hasSpeech(), "single impulse is not speech");
        VoiceEndpoint noise = new VoiceEndpoint();
        check(feed(noise, .03, 1500), "continuous noise has a 30-second bound");
        System.out.println("VoiceEndpoint: 5 scenarios passed");
    }
}
