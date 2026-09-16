import os

from flask import Flask, render_template_string, request

from app.config import Config
from app.routes.webhook import webhook_bp

TEST_PAGE = """<!DOCTYPE html>
<html lang=\"fr\">
<head>
  <meta charset=\"utf-8\" />
  <title>ConvertTrack - Test Website</title>
  <style>
    body { font-family: sans-serif; max-width: 720px; margin: 48px auto; padding: 0 16px; }
    h1 { color: #1f93ff; }
  </style>
</head>
<body>
  <h1>ConvertTrack - Canal Website</h1>
  <p>Utilisez la bulle de chat en bas a droite pour envoyer un message test.</p>
  <p>Exemple : <em>Bonjour, quel est le prix de votre produit ?</em></p>
  <script>
    (function(d,t) {
      var BASE_URL=\"{{ base_url }}\";
      var g=d.createElement(t),s=d.getElementsByTagName(t)[0];
      g.src=BASE_URL+\"/packs/js/sdk.js\";
      g.async = true;
      s.parentNode.insertBefore(g,s);
      g.onload=function(){
        window.chatwootSDK.run({
          websiteToken: \"{{ website_token }}\",
          baseUrl: BASE_URL
        })
      }
    })(document,\"script\");
  </script>
</body>
</html>"""


def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    app.register_blueprint(webhook_bp)

    @app.after_request
    def add_cors_headers(response):
        origin = app.config.get("CHATWOOT_BASE_URL", "http://127.0.0.1:3000")
        if request.headers.get("Origin") == origin:
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Access-Control-Allow-Headers"] = "Content-Type"
        return response

    @app.get("/health")
    def health():
        return {"status": "ok", "service": "converttrack"}, 200

    @app.get("/test")
    def test_website():
        token_path = os.getenv("WEBSITE_TOKEN_PATH", "/shared/website_token")
        website_token = ""
        if os.path.isfile(token_path):
            website_token = open(token_path, encoding="utf-8").read().strip()

        if not website_token:
            return {"error": "website_token manquant, relancez converttrack-setup"}, 503

        return render_template_string(
            TEST_PAGE,
            base_url=app.config["CHATWOOT_BASE_URL"],
            website_token=website_token,
        )

    return app
