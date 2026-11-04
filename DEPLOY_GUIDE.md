# ASO INOVISION: Supabase deployment guide (step by step)

What you will have at the end:
- Your website reads its services, industries, insights, jobs and headline text from Supabase.
- A hidden admin page where you add, edit and delete all of that, and manage consultation requests and job applications.
- "Book a consultation" and "Apply" forms that save to Supabase and alert you by email (and WhatsApp once Meta approves it).

If Supabase is not set up or is unreachable, the website still shows the built-in content, so visitors never see a blank page.

---------------------------------------------------------------------------------------------------

## What you need first
1. A computer with **Node.js** installed (nodejs.org, the "LTS" version).
2. A free **Supabase** account (supabase.com).
3. A free **Netlify** account (netlify.com) for the website. Supabase hosts the database and forms; Netlify hosts the pages. Read the plan note in Step 9 before you deploy.
4. A free **Resend** account (resend.com) for email alerts. Sign up with **asoinovisionpro@gmail.com**.
5. Optional, later: a Meta (Facebook) Business account for WhatsApp alerts.

Unzip `asoinovision-deploy.zip`. All commands below run in a terminal opened inside that unzipped folder.

---------------------------------------------------------------------------------------------------

## Step 1. Create the Supabase project
1. Sign in at supabase.com and click **New project**.
2. Choose your organisation, give the project a name (for example `asoinovision`).
3. Set a strong **Database password** and save it in a password manager. You will rarely need it.
4. Pick the **region** closest to Nigeria that is offered (Europe or South Africa if available).
5. Click **Create new project** and wait a couple of minutes until it finishes.

## Step 2. Create the database
1. In the left menu click **SQL Editor**, then **New query**.
2. Open `supabase/setup.sql` from the unzipped folder, copy **everything**, and paste it into the editor.
3. Click **Run**. You should see "Success". Run it **only once**. If you run it twice you will get "already exists" errors, which are harmless but mean it was already done.
4. Click **Table Editor**. You should see these tables with content already in them: `services`, `industries`, `insights`, `jobs`, `site_sections`, plus empty `consultations`, `applications` and `admins`.

## Step 3. Copy your project's address and public key
1. Click the **gear icon (Project Settings)**, then **API** (called "Data API" or "API Keys" in newer dashboards).
2. Copy the **Project URL** (looks like `https://abcdxyz.supabase.co`).
3. Copy the **anon public key** (newer dashboards may call it the **publishable key**). It is safe to put in your website.
4. **Never** put the `service_role` or "secret" key in any website file. Only the Edge Functions use it, and Supabase supplies it to them automatically.
5. Also note your **Project ref**: it is the part of the URL before `.supabase.co` (here `abcdxyz`).

## Step 4. Create your admin login
1. Click **Authentication**, then **Users**, then **Add user**, then **Create new user**.
2. Enter your email (for example `asoinovisionpro@gmail.com`) and a strong password. Tick **Auto Confirm User** if shown.
3. Go back to **SQL Editor**, **New query**, paste this (change the email if you used a different one) and **Run**:

```sql
insert into public.admins (user_id, email)
select id, email from auth.users where email = 'asoinovisionpro@gmail.com';
```
4. Only people listed in the `admins` table can use the admin page. To add another admin later, create their user and run the same statement with their email.

## Step 5. Lock down sign-ups
1. In **Authentication**, open the settings for sign-in/providers (the menu name varies slightly between dashboard versions).
2. Still in Authentication, open **URL Configuration** and set **Site URL** to your website address (for example `https://aso-inovision.netlify.app`).
3. Turn **off** "Allow new users to sign up". This means strangers cannot create accounts. Only users you create yourself can sign in.
4. Optional but recommended: turn on multi-factor authentication for your own login, and use a long unique password.

## Step 6. Deploy the form functions
These two small programs receive the consultation form and job applications, save them, and send you alerts.

1. In the terminal run `npx supabase login` and approve the browser prompt.
2. Link your project (use your Project ref from Step 3): `npx supabase link --project-ref abcdxyz`
3. Deploy:
```
npx supabase functions deploy submit-consultation --no-verify-jwt
npx supabase functions deploy submit-application --no-verify-jwt
```
   `--no-verify-jwt` is needed because website visitors are not signed in. The functions protect themselves by checking and limiting what they accept.
4. Your functions now live at `https://abcdxyz.supabase.co/functions/v1/submit-consultation` and `.../submit-application`. The website builds that address from your Project URL, so you do not need to type it anywhere.

## Step 7. Set the secrets (email and WhatsApp alerts)
1. **Your website address** (so only your site can call the functions). Use your real address; update it when you get your own domain:
```
npx supabase secrets set ALLOWED_ORIGIN=https://aso-inovision.netlify.app
```
   To allow more than one address (for example your own domain later, or a Netlify deploy-preview address while testing), separate them with commas: `ALLOWED_ORIGIN=https://aso-inovision.netlify.app,https://www.yourdomain.com`.
2. **Email alerts with Resend.** In Resend create an API key, then:
```
npx supabase secrets set RESEND_API_KEY=re_xxxxxxxx NOTIFY_EMAIL=asoinovisionpro@gmail.com
```
   Resend's free test sender only delivers to the email you signed up with. Sign up with asoinovisionpro@gmail.com so alerts reach you, or verify your own domain in Resend and set `MAIL_FROM` to an address on it.
3. **WhatsApp alerts (later).** WhatsApp only lets a business send a first message using a pre-approved template. In Meta Business Suite set up the WhatsApp Business Platform, create a message template named `new_enquiry` with one body variable, wait for approval, then:
```
npx supabase secrets set WHATSAPP_TOKEN=xxxx WHATSAPP_PHONE_ID=xxxx NOTIFY_WHATSAPP=2349068290425 WHATSAPP_TEMPLATE=new_enquiry
```
   Until then, the email alert is your notification. Meta's setup and rules change, so follow their current documentation.

## Step 8. Connect the website and the admin page
1. Open `public/index.html` in a text editor (Notepad is fine). Search for `var SB_URL=""`.
2. Change it to your values, for example: `var SB_URL="https://abcdxyz.supabase.co",SB_KEY="your-anon-public-key";`
3. Save. Open `public/admin/index.html`, find the same `var SB_URL=""` line, and put in the same two values. Save.

## Step 9. Put the website online on Netlify (free)
**Plan note.** Netlify's free plan allows business use. It runs on a monthly allowance of **300 credits**: each successful production deploy costs about 15 credits, and visitor bandwidth costs credits too (reported as about 20 credits per GB). Each visit to your home page downloads roughly 1 MB, so the free allowance covers about 15 GB, which is on the order of 15,000 visits a month if you deploy rarely. **If the credits run out, Netlify pauses your site until the next month or until you upgrade.** Check the current numbers at netlify.com/pricing, and watch the usage page. If you expect more traffic, Netlify's paid plan or Cloudflare Pages (unlimited bandwidth on its free plan) are alternatives, and nothing else in this guide changes.

**Option A (simplest): drag and drop**
1. Sign in at netlify.com. Open **Projects** (or **Sites**) and choose **Add new project > Deploy manually** (the wording varies slightly).
2. Drag the **`public` folder** from the unzipped folder onto the upload area. The folder includes a `_headers` file that keeps the admin page out of search engines.
3. Netlify gives you an address like `https://random-name.netlify.app`.
4. To update the site later, drag the `public` folder onto the **Deploys** page again. Each deploy uses credits, so batch your changes.

**Option B: through GitHub (updates deploy automatically)**
1. Create a GitHub repository and upload the contents of the unzipped folder. It contains no secrets: the only key in it is the public anon key.
2. In Netlify choose **Add new project > Import an existing project**, pick GitHub, and select the repository.
3. Settings: leave **Build command** empty and set **Publish directory** to `public` (the included `netlify.toml` already says this). Click **Deploy**.

**Option C: from the terminal**
1. `npx netlify-cli login`
2. `npx netlify-cli deploy --dir=public --prod` and follow the prompts to create the site.

**Choose a nicer address.** In your site's settings open **Site configuration > Site details > Change site name** and pick something like `aso-inovision`, which gives `https://aso-inovision.netlify.app`.

**Your own domain.** Open **Domain management** and add it. Netlify provides the free HTTPS certificate. Then add the new address to `ALLOWED_ORIGIN` (Step 7) and to the Supabase **Site URL** (Step 5).

Your site is at your Netlify address. The admin page is that address followed by `/admin/`.

## Step 10. Test everything
1. Open your site. The **Contact** page: fill and send the consultation form. In Supabase **Table Editor > consultations** the row should appear, and an email should arrive.
2. **Careers**: open a role, click **Apply**, upload a CV, check the form fills in, submit. Check `applications` and the private `cvs` storage bucket.
3. Open `/admin/`, sign in, and go to **Jobs**. Change a job title, save, then refresh the Careers page. The change should be there.
4. Try **Insights > Add new**, tick **Published**, save, and open **Our Insights**.

---------------------------------------------------------------------------------------------------

## Using the admin page day to day
- **Dashboard:** counts of new requests, new applications, open jobs and published insights.
- **Consultations / Applications:** open one to read it, change its status, add private notes, or delete it. Applications have an **Open CV** button. **Export CSV** downloads consultations for a spreadsheet.
- **Jobs:** add, edit, delete, close a role (untick "Open"), and set the order. Tick "internship" to show the B.Sc./OND/HND fields on the application form.
- **Insights:** write articles. Use a blank line between paragraphs, `## Heading`, `- bullet`, and `**bold**`. Untick "Published" to keep a draft hidden.
- **Services and sectors:** add, edit, delete and reorder every service, choose its group, and tick "Show on the home page" for up to six.
- **Industries we serve:** add, edit, delete and reorder.
- **Site text:** edit the home page headline, the paragraphs on the home, About, Services, Industries, Careers and Contact pages.
- **Images:** upload (up to 3 MB) or paste a link. Leave empty to use the brand shapes.

## Keeping it safe
- The admin page is not linked anywhere on your site, and it asks for a login that only people in the `admins` table can pass. To make the address harder to guess, rename the `public/admin` folder (for example to `staff-7f3k`) before you deploy.
- CVs and consultation requests contain personal data. Only admins can read them. Tell applicants how long you keep their details, and delete old ones from the admin page.
- Keep your database password, `service_role` key, Resend key and WhatsApp token private. Never put them in the website files or send them in chat.
- Supabase's free plan has limits (for example, inactive free projects can be paused, and backups are limited). Check the current plan details at supabase.com/pricing. If the project is paused, the website falls back to its built-in content, but forms and the admin page stop until you resume it.

## If something does not work
- **The site still shows old content:** check `SB_URL` and `SB_KEY` in `public/index.html` have no typos, then redeploy (drag the `public` folder again, push to GitHub, or run `npx netlify-cli deploy --dir=public --prod`) and hard refresh.
- **Admin says "not an administrator":** re-run the Step 4 `insert into public.admins` statement with the exact email you signed in with.
- **Form says "Online submission is not switched on yet":** `SB_URL` is empty in `public/index.html`.
- **Form says something went wrong:** check `ALLOWED_ORIGIN` matches your site address exactly (including `https://`), then look in Supabase **Edge Functions > Logs**.
- **No email arrives:** check `RESEND_API_KEY`, and that you signed up to Resend with the same email as `NOTIFY_EMAIL`. Also check spam.
