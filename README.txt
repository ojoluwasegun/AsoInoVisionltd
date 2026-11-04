ASO INOVISION website, admin panel and database

public/index.html       The website (Home, Services, Industries, About, Our Insights, Careers, Apply, Contact)
public/admin/index.html Hidden admin page. Not linked anywhere. Manage jobs, insights, services, industries, site text, consultations, applications
supabase/setup.sql      The whole database, security rules, storage and starting content
supabase/functions/     submit-consultation and submit-application (save the forms, then alert you)
DEPLOY_GUIDE.md         START HERE: full step-by-step setup
archive/                ThesisFlow site and platform prototype. Not deployed.

Hosting: website on Netlify (free plan allows business use but is credit-limited), database and forms on Supabase.
Quick start: read DEPLOY_GUIDE.md, Step 1 to Step 10.
