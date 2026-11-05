# CSDF 1B ARENA

**Learn. Compete. Connect.** A responsive class quiz platform for USTED Cybersecurity and Digital Forensics, Level 100, CSDF 1B.

## What this version includes

- Student account registration and login
- Unique class index numbers restricted to **101–200**
- Student dashboard with points and class rank
- Competition centre with course categories and timed multiple-choice quizzes
- Class leaderboard (best score per competition is counted, so repeated practice does not endlessly inflate points)
- Admin dashboard to create/publish competitions and add questions
- WhatsApp class-group invitation link
- Supabase Auth, PostgreSQL and Row Level Security
- Server-side answer checking: correct answers are not sent to student browsers
- Responsive layout for desktop and mobile browsers

## Important scope note

This is the secure individual-quiz foundation. Team battles, certificates, daily streaks, question import from PDFs, and advanced analytics are planned extensions, not active features in this build. The countdown is displayed in the browser; this pilot should be used for friendly class learning, not formal examinations or high-stakes prizes. A later release can add server-enforced quiz sessions and team scoring.

## 1. Create the Supabase backend

1. Create a project at <https://supabase.com>.
2. Open **SQL Editor → New query**.
3. Paste the complete contents of `supabase/schema.sql` and run it. Use a new/empty project for this first setup.
4. Open **Project Settings → API** (or **API Keys**) and copy the Project URL and anon/public key.
5. Never put the `service_role` key in the website or GitHub.

## 2. Configure the website

Open `config.js` and replace the three placeholder values:

- `YOUR_SUPABASE_PROJECT_URL`
- `YOUR_SUPABASE_ANON_PUBLIC_KEY`
- `YOUR_WHATSAPP_GROUP_INVITE_LINK`

To get the group invitation URL, open the WhatsApp group → group info → **Invite via link** → **Copy link**. Use the group invite URL, not a personal phone number. Treat the invite link as private because people who have it may be able to join.

## 3. Make your own account an administrator

1. Open the website after configuring Supabase.
2. Register using your own assigned index number (101–200).
3. Confirm your email if Supabase requests it, then log in once.
4. In Supabase SQL Editor, run the following separately, replacing `101` with your actual class index:

```sql
update public.profiles
set role = 'admin'
where index_number = 101;
```

5. Log out and log back in. The Admin dashboard should appear.

Only promote trusted organisers. Do not share your Supabase account or service-role key.

## 4. Publish with GitHub and Netlify

1. Extract this ZIP on your computer.
2. Create a GitHub repository named `csdf-1b-arena`.
3. Upload the **contents** of the `CSDF-1B-ARENA` folder to the repository root (so `index.html` is at the root).
4. In Netlify, choose **Add new site → Import an existing project → GitHub** and select the repository.
5. Leave the build command blank and set the publish directory to `.`.
6. Deploy the site.
7. In Supabase, open **Authentication → URL Configuration**. Set the Site URL to your Netlify website address and add that same address under Redirect URLs.

## 5. Create your first competition

1. Log in as the administrator.
2. In Admin dashboard, create a competition (for example, **Cybersecurity Essentials – Week 1**).
3. Choose a category, add a short description and set the time limit.
4. Add questions with four options, select the correct option and include a short explanation for your own reference.
5. Publish the competition when it is ready. Students will see published competitions in the Competition Centre.

Start with 5–10 questions from lecturer-provided handouts. Check spelling and correct answers before publishing.

## 6. Local preview

You can open `index.html` for a quick visual preview, but login and database features require the Supabase configuration. For a local web server, use the VS Code Live Server extension or run a simple static server from this folder.

## Troubleshooting

- **Setup required message:** check the URL and anon key in `config.js`; save and reload.
- **Email confirmation:** check the email inbox and spam folder, then log in after confirming.
- **Index already registered:** each index number can belong to only one account; check that the number is correct.
- **Admin dashboard missing:** confirm your own profile's role in Supabase, then log out and back in.
- **No competitions appear:** create a competition as admin and set Status to Publish now.
- **WhatsApp button does nothing:** add the group invite URL to `config.js`.

## Project structure

```text
CSDF-1B-ARENA/
├── index.html
├── styles.css
├── app.js
├── config.js
├── netlify.toml
├── .gitignore
├── README.md
└── supabase/
    └── schema.sql
```

Built as a free-tier-friendly starter using HTML, CSS, JavaScript, Supabase and Netlify. Provider free-tier limits and terms can change; keep backups of your database and code.
