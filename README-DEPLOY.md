# Deploying IRONPEAK FITNESS on your own server

This package contains everything needed to run the website + the free-pass inquiry form on your own Linux server (Ubuntu example). The site is plain static files; the form runs on a small Python backend that saves inquiries to MongoDB.

## What's inside
```
frontend/    -> Built website (static files, ready to host with nginx/Apache/any static server)
backend/     -> Python (FastAPI) app that receives form inquiries and stores them in MongoDB
nginx/       -> Ready-made nginx site config
systemd/     -> Service file so the backend auto-starts and stays running
```

## Requirements on your server
- Python 3.10+ (`python3 --version`)
- MongoDB running locally, or a free MongoDB Atlas connection string
- nginx (or any web server that can host static files)

---

## Fastest path (Ubuntu 22.04 / 24.04)
Upload the zip, unzip it, then:
```bash
cd ironpeak-fitness-deploy
sudo bash install-ubuntu.sh
```
The script installs nginx + MongoDB, starts the inquiry-form backend, publishes the website and prints your URL. Optional: edit the 3 variables at the top of the script first (domain, database name). The manual steps below do the same thing by hand.

---

## Step 1 — Upload the package
Upload and unzip, for example to `/opt/ironpeak`:
```bash
sudo mkdir -p /opt/ironpeak && cd /opt/ironpeak
sudo unzip ironpeak-fitness-deploy.zip
```

## Step 2 — Start the backend
```bash
cd /opt/ironpeak/backend
python3 -m venv venv
venv/bin/pip install -r requirements.txt
cp .env.example .env
nano .env
```
Edit `.env`:
- `MONGO_URL` — your MongoDB address. Local default: `mongodb://localhost:27017`. For Atlas, paste your connection string.
- `DB_NAME` — pick a production name, e.g. `ironpeak_production`
- `CORS_ORIGINS` — set to your domain, e.g. `https://yourdomain.com`

Test it: `venv/bin/uvicorn server:app --host 0.0.0.0 --port 8001` then open `http://YOUR_SERVER_IP:8001/api/` — you should see a message. Ctrl+C to stop.

Install as a service (so it survives reboots):
```bash
sudo cp /opt/ironpeak/systemd/ironpeak-backend.service /etc/systemd/system/
# Open the file and make sure the paths inside match /opt/ironpeak/backend
sudo systemctl daemon-reload
sudo systemctl enable --now ironpeak-backend
```

## Step 3 — Host the website with nginx
```bash
sudo mkdir -p /var/www/ironpeak
sudo cp -r /opt/ironpeak/frontend/* /var/www/ironpeak/
sudo cp /opt/ironpeak/nginx/ironpeak.conf /etc/nginx/sites-available/ironpeak
sudo nano /etc/nginx/sites-available/ironpeak   # replace yourdomain.com with your domain or server IP
sudo ln -s /etc/nginx/sites-available/ironpeak /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```
This serves the website and transparently forwards `/api/...` to the backend — no cross-origin setup needed.

## Step 4 — HTTPS (optional but recommended)
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com
```

## Done — verify
Open your site, scroll to the form, submit a test inquiry, then check it was saved:
```bash
curl http://yourdomain.com/api/inquiries
```

## Common issues
- **"Couldn't send right now" toast on the form** — the backend isn't reachable: `sudo systemctl status ironpeak-backend` and `sudo nginx -t`.
- **Changing the form to post somewhere else** — the build calls `/api` on the same domain. If you must host the backend on a different domain, ask me to rebuild with that domain configured.
- **Sub-folder hosting** — the build uses relative paths, so it also works in a sub-folder (e.g. `yourdomain.com/gym/`).

## Updating content later
Prices, timings, review quotes and the address live in the site's code. Ask me to change them and rebuild this zip, or deploy future builds the same way (overwrite `/var/www/ironpeak` + restart backend).
