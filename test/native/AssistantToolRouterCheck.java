import id.sahabatnetra.app.AssistantToolRouter;

public final class AssistantToolRouterCheck {
    private static void check(String question, String expected) {
        if (!java.util.Objects.equals(expected, AssistantToolRouter.route(question)))
            throw new AssertionError(question);
    }
    public static void main(String[] args) {
        check("Di depan saya ada apa?", "detect_objects");
        check("Didepan ada apa", "detect_objects");
        check("Bacakan tulisan di depan saya", "read_text");
        check("Baca ini", "read_text");
        check("Bacakan cerita pendek", null);
        check("Berapa satu tambah satu?", null);
        System.out.println("AssistantToolRouter: 6 scenarios passed");
    }
}
