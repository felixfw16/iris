package id.sahabatnetra.app;

import java.util.regex.Pattern;

/** Fast path for explicit camera requests; other requests go to the model. */
public final class AssistantToolRouter {
    private static final Pattern TEXT = Pattern.compile("(?i)\\b(teks|tulisan)\\b|\\b(baca|bacakan)\\s+(ini|itu)\\b");
    private static final Pattern SCENE = Pattern.compile("(?i)(di\\s*depan|di\\s*sekitar|ada apa|apa (ini|itu)|\\b(lihat|kamera)\\b)");
    public static String route(String question) {
        if (TEXT.matcher(question).find()) return "read_text";
        if (SCENE.matcher(question).find()) return "detect_objects";
        return null;
    }
}
