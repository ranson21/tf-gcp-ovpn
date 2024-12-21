from flask import Flask, request, jsonify, render_template_string, send_file
from google.oauth2 import id_token
from google.auth.transport import requests
import os
import json
import tempfile
from functools import wraps

app = Flask(__name__)

CLIENT_ID = os.environ.get("CLIENT_ID")
ALLOWED_DOMAIN = os.environ.get("ALLOWED_DOMAIN")
EXTERNAL_IP = os.environ.get("EXTERNAL_IP")


def require_auth(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return jsonify({"error": "No authorization token provided"}), 401

        token = auth_header.split(" ")[1]
        try:
            idinfo = id_token.verify_oauth2_token(token, requests.Request(), CLIENT_ID)

            email = idinfo.get("email", "")
            if not email.endswith("@" + ALLOWED_DOMAIN):
                return jsonify({"error": "Invalid domain"}), 403

            return f(email, *args, **kwargs)
        except Exception as e:
            return jsonify({"error": str(e)}), 401

    return decorated_function


def generate_ovpn_config(email):
    config = f"""client
dev tun
proto udp
remote {EXTERNAL_IP} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-CBC
key-direction 1
verb 3
auth-user-pass
auth-nocache

<ca>
{open('/etc/openvpn/ca.crt').read()}
</ca>

<cert>
{open('/etc/openvpn/client.crt').read()}
</cert>

<key>
{open('/etc/openvpn/client.key').read()}
</key>

<tls-auth>
{open('/etc/openvpn/ta.key').read()}
</tls-auth>
"""
    return config


@app.route("/")
def index():
    html = (
        """
    <!DOCTYPE html>
    <html>
    <head>
        <title>OpenVPN Authentication</title>
        <script src="https://accounts.google.com/gsi/client" async defer></script>
        <!-- OpenVPN favicon -->
        <link rel="icon" type="image/png" href="data:image/png;base64,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">
        <style>
            body { 
                font-family: Arial, sans-serif; 
                margin: 0; 
                padding: 0;
                display: flex;
                justify-content: center;
                align-items: center;
                min-height: 100vh;
                background-color: #f5f5f5;
            }
            .container { 
                max-width: 600px; 
                margin: 20px;
                padding: 40px;
                background: white;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            h1 {
                color: #333;
                margin-bottom: 20px;
            }
            p {
                color: #666;
                line-height: 1.6;
            }
            .status {
                margin-top: 20px;
                padding: 15px;
                border-radius: 4px;
                background: #e8f5e9;
                color: #2e7d32;
            }
            .download-btn {
                display: none;
                background-color: #1a73e8;
                color: white;
                padding: 12px 24px;
                border: none;
                border-radius: 4px;
                cursor: pointer;
                font-size: 16px;
                margin-top: 20px;
            }
            .download-btn:hover {
                background-color: #1557b0;
            }
            .hidden {
                display: none;
            }
            #signInDiv {
                margin-top: 20px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>OpenVPN Authentication Portal</h1>
            <p>To download your VPN configuration:</p>
            <ol>
                <li>Sign in with your organization account</li>
                <li>Download your personalized OpenVPN configuration file</li>
                <li>Import the configuration into your OpenVPN client</li>
            </ol>
            
            <div id="signInDiv"></div>
            <button id="downloadBtn" class="download-btn hidden">Download OpenVPN Config</button>
            
            <div class="status">
                Server Status: Active ✓
            </div>
        </div>

        <script>
            let authToken = '';
            
            window.onload = function () {
                google.accounts.id.initialize({
                    client_id: '"""
        + CLIENT_ID
        + """',
                    callback: handleCredentialResponse,
                    auto_select: true,
                    context: 'signin',
                    ux_mode: 'redirect',
                    redirect_uri: 'https://' + window.location.hostname + '/_gcp_gatekeeper/authenticate',
                });
                google.accounts.id.renderButton(
                    document.getElementById("signInDiv"),
                    { 
                        theme: "outline", 
                        size: "large",
                        type: "standard",
                        shape: "rectangular",
                        text: "signin_with",
                        logo_alignment: "left"
                    }
                );
            };

            function handleCredentialResponse(response) {
                authToken = response.credential;
                document.getElementById('downloadBtn').classList.remove('hidden');
            }

            document.getElementById('downloadBtn').addEventListener('click', async () => {
                try {
                    const response = await fetch('/download-config', {
                        headers: {
                            'Authorization': 'Bearer ' + authToken
                        }
                    });
                    
                    if (response.ok) {
                        const blob = await response.blob();
                        const url = window.URL.createObjectURL(blob);
                        const a = document.createElement('a');
                        a.href = url;
                        a.download = 'client.ovpn';
                        document.body.appendChild(a);
                        a.click();
                        window.URL.revokeObjectURL(url);
                        document.body.removeChild(a);
                    } else {
                        const error = await response.json();
                        alert('Error: ' + error.error);
                    }
                } catch (error) {
                    alert('Error downloading configuration: ' + error);
                }
            });
        </script>
    </body>
    </html>
    """
    )
    return render_template_string(html)


@app.route("/download-config")
@require_auth
def download_config(email):
    try:
        config = generate_ovpn_config(email)

        # Create a temporary file
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".ovpn", delete=False
        ) as temp_file:
            temp_file.write(config)
            temp_path = temp_file.name

        # Send the file and then delete it
        return_value = send_file(
            temp_path,
            as_attachment=True,
            download_name=f"client.ovpn",
            mimetype="application/x-openvpn-profile",
        )

        # Schedule the temporary file for deletion
        @return_value.call_on_close
        def cleanup():
            try:
                os.unlink(temp_path)
            except:
                pass

        return return_value

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/auth", methods=["POST"])
def authenticate():
    try:
        token = request.form.get("token")
        if not token:
            return jsonify({"error": "No token provided"}), 400

        idinfo = id_token.verify_oauth2_token(token, requests.Request(), CLIENT_ID)

        email = idinfo.get("email", "")
        if not email.endswith("@" + ALLOWED_DOMAIN):
            return jsonify({"error": "Invalid domain"}), 403

        return jsonify({"success": True, "email": email}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.route("/health", methods=["GET"])
def health_check():
    return jsonify({"status": "healthy"}), 200


if __name__ == "__main__":
    if not all([CLIENT_ID, ALLOWED_DOMAIN, EXTERNAL_IP]):
        raise ValueError(
            "CLIENT_ID, ALLOWED_DOMAIN, and EXTERNAL_IP must be set in environment variables"
        )
    app.run(host="127.0.0.1", port=8081)
