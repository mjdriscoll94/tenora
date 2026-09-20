# Tenora Branding Host

This folder is a standalone static Vercel project for public Tenora authentication assets. Keeping it separate from the API means Auth0 can load the logo without waking the Render service.

## Deploy

Import the Tenora GitHub repository into Vercel and configure:

- Root Directory: `Branding`
- Framework Preset: `Other`
- Build Command: leave empty
- Output Directory: leave empty

Vercel will deploy each push to `main`. After the first production deployment, use the stable production URL followed by `/tenora-icon.png` as the Auth0 Universal Login logo URL.
