package fr.edp.app;

import android.app.Activity;
import android.app.Dialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import org.json.JSONObject;

/**
 * EDP pour Android : affiche le site en plein écran et s'occupe de la connexion à l'ENT.
 * Le site appelle EDPAndroid.entLogin(url, schéma) ; on ouvre la vraie page de l'ENT (ÉduConnect compris),
 * et quand l'ENT renvoie vers « skoapp-prod://…?code=… », on rend ce lien au site via window.__edpEnt(ok, lien).
 * ponytail: seule la connexion ENT est native ; rappels, position, etc. restent ceux du site.
 */
public class MainActivity extends Activity {
    static final String SITE = "https://cartable.bizzarirobin66.workers.dev/";
    static final String HOST = Uri.parse(SITE).getHost();
    private WebView web;
    private Dialog entDialog;

    private static void setup(WebView w) {
        WebSettings s = w.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        // certaines pages de connexion refusent les « WebView » : on se présente comme Chrome
        s.setUserAgentString(s.getUserAgentString().replace("; wv", ""));
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(w, true);
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        web = new WebView(this);
        setup(web);
        web.addJavascriptInterface(new Bridge(), "EDPAndroid");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                Uri u = r.getUrl();
                if (HOST.equals(u.getHost())) return false;          // EDP reste dans l'appli
                try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Exception e) { }
                return true;                                         // le reste s'ouvre dans le navigateur
            }
        });
        setContentView(web);
        if (state != null) web.restoreState(state); else web.loadUrl(SITE);
    }

    @Override protected void onSaveInstanceState(Bundle out) { super.onSaveInstanceState(out); web.saveState(out); }
    @Override protected void onPause() { super.onPause(); CookieManager.getInstance().flush(); }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) web.goBack(); else super.onBackPressed();
    }

    private void finishEnt(boolean ok, String data) {
        if (entDialog == null) return;                               // déjà terminé
        Dialog d = entDialog; entDialog = null; d.dismiss();
        web.evaluateJavascript("window.__edpEnt&&window.__edpEnt(" + ok + "," + JSONObject.quote(data) + ")", null);
    }

    private void openEnt(String url, final String scheme) {
        if (!url.startsWith("https://")) { web.evaluateJavascript("window.__edpEnt&&window.__edpEnt(false,'Adresse invalide.')", null); return; }
        WebView w = new WebView(this);
        setup(w);
        w.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                Uri u = r.getUrl();
                if (scheme.equalsIgnoreCase(u.getScheme())) { finishEnt(true, u.toString()); return true; }
                return !"https".equals(u.getScheme()) && !"http".equals(u.getScheme());
            }
        });
        entDialog = new Dialog(this, android.R.style.Theme_DeviceDefault_NoActionBar);
        entDialog.setContentView(w);
        entDialog.setOnCancelListener(x -> finishEnt(false, "Connexion à l’ENT annulée"));   // bouton retour
        entDialog.show();
        w.loadUrl(url);
    }

    class Bridge {
        @JavascriptInterface
        public void entLogin(final String url, final String scheme) {
            runOnUiThread(() -> openEnt(url, scheme == null || scheme.isEmpty() ? "skoapp-prod" : scheme));
        }
    }
}
