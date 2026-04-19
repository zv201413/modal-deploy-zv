import modal
import subprocess
import os
import base64

INSTALL_SCRIPT_VERSION = 3


def _modal_function_options():
    """Build optional kwargs for @app.function from environment (CI / local deploy)."""
    opts = {}
    raw_region = os.environ.get("MODAL_REGION", "").strip()
    if raw_region:
        parts = [p.strip() for p in raw_region.split(",") if p.strip()]
        if parts:
            opts["region"] = parts
    if os.environ.get("MODAL_NONPREEMPTIBLE", "").strip() == "true":
        opts["nonpreemptible"] = True
    return opts


app = modal.App("vevc-app")
vevc_image = (
    modal.Image.debian_slim()
        .apt_install("curl", "unzip", "supervisor", "procps")
        .add_local_file("install.sh", "/root/install.sh", copy=True)
        .run_commands("bash /root/install.sh")
        .pip_install("fastapi[standard]")
)

_supervisor_started = False

def start_supervisor():
    global _supervisor_started
    if not _supervisor_started:
        os.environ["ENABLE_SC"] = "true" if "KPAL" in os.environ else "false"
        subprocess.run(["supervisord"], env=os.environ.copy())
        _supervisor_started = True

@app.function(
    image=vevc_image,
    secrets=[modal.Secret.from_name("vps")],
    min_containers=1,
    max_containers=1,
    scaledown_window=1200,
    **_modal_function_options(),
)
@modal.asgi_app()
def main():
    from fastapi import FastAPI
    from fastapi.responses import PlainTextResponse

    start_supervisor()
    web_app = FastAPI()
    uuid = os.environ["U"]

    @web_app.get("/status", response_class=PlainTextResponse)
    async def status():
        start_supervisor()
        return "UP"

    @web_app.get(f"/{uuid}", response_class=PlainTextResponse)
    async def sub():
        start_supervisor()
        domain = os.environ["D"]
        sub_url = f"vless://{uuid}@{domain}:443?encryption=none&security=tls&sni={domain}&fp=chrome&insecure=0&allowInsecure=0&type=ws&host={domain}&path=%2F%3Fed%3D2560#modal-ws-argo"
        return base64.b64encode(sub_url.encode("utf-8"))

    return web_app
