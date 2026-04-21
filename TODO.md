# ClaudeHurst Communications Push TODO

## Branch discipline

All Outlook, Teams, email, chat, and continuous communication work should stay on `feature/microsoft-communications-push` until the feature is stable enough to merge.

## Product principle

ClaudeHurst remains the system of record. Outlook and Teams are delivery surfaces. Anything involving customer communication, chat, reminders, approvals, handoffs, or status changes should be pushed continuously rather than requiring users to manually check the CRM.

Every communication feature should answer three questions: who needs to know, through which channel, and how quickly.

## Built in this branch

- Microsoft connection model and migration.
- Communication push event ledger.
- Microsoft connection settings page.
- Microsoft Graph client scaffold.
- Outlook delivery service.
- Outlook calendar service.
- Teams notification service.
- Solid Queue background job for communication pushes.
- Sidebar link to Microsoft settings.
- Environment-variable example file.

## Next implementation passes

### Outlook calendar

- Add create-meeting buttons from deal, company, contact, and production run pages.
- Save the returned Microsoft event id to the push event ledger.
- Add CRM record links in event bodies.

### Outlook delivery

- Add customer follow-up flows for quotes, invoices, and deal stage changes.
- Log every CRM-generated outbound message as an activity.
- Add templates for quote follow-up, invoice reminder, production update, and customer onboarding.

### Teams notifications

- Add event routing from business events to role channels.
- Initial pushes: new deal, deal stage advance, quote approved, production delay, low inventory, overdue invoice, payment received, and task assignment.

### Reliability

- Add retry policy for failed Microsoft Graph calls.
- Add deduplication tests.
- Add failed-push admin visibility.
- Add user/role notification preferences.
- Add refresh handling when Microsoft connection expires.

## Local setup

Run these locally after switching to this branch:

```bash
bundle install
DATABASE_PASSWORD=password bin/rails db:migrate
bin/dev
```

Copy `.env.microsoft.example` into the local `.env` file and fill in the Microsoft Entra app values.
