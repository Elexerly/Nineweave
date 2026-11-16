# Account deletion: proposed policy amendment

**Draft for the separately implemented deletion feature. Not a statement that the feature is deployed.** Publish only after the authenticated server endpoint and confirmed Options flow are deployed and tested together. Use the designated game/privacy contact, **escapetheavalanchedeux@gmail.com**, when updating the served policy; its existing placeholder has not been changed by this draft. This draft is a description of implementation, not a legal compliance determination.

## Designated privacy contact

For privacy questions, additional identifying-data removal requests, or help with account deletion, contact **escapetheavalanchedeux@gmail.com**. This is the owner-designated contact as of November 16, 2026.

## Proposed Data deletion section

When the Delete account option is available in Options, you can request permanent deletion of your current game account. You must leave or finish active matches first. Leave a registering tournament before deletion; if a tournament you joined has started, wait until it ends, even if you have been eliminated or withdrawn. The game asks you to confirm before submitting the request.

Deletion removes your account profile, screen name, email address and verification records, account credentials, account statistics, purchase/unlock records held in that profile, consent record, your stored chat messages, block relationships and tournament membership records. Reports submitted by you or about your account, including their notes and saved chat copies, are also removed. You lose access to this account and its saved online progress.

Shared match results and tournament history can remain so other players keep their results. Your account links are removed, and stored screen-name labels belonging to you are replaced with `####`. Finished rooms involving the deleted account are closed to prevent rematches with a deleted account. Other players' account statistics are not reset. This does not guarantee anonymity: people who remember a match or know its date and participants may still recognize the gameplay record. Deletion cannot remove screenshots or copies already held by other people.

## Operational limits to disclose before publication

- This endpoint deletes/scrubs the active game database only. Hosting logs, email-provider records and database backups are not erased by this operation. Their retention periods and any deletion procedure must be confirmed with the configured providers before the final policy promises a period or coverage.
- Another player's free-text message or a report unrelated by account ID could mention a person. The endpoint does not scan and infer identities in all other users' text. Do not promise removal of every possible identifying mention; provide a working contact for additional requests.
- A frontend must clear local account credentials/profile data only after confirmed success; it must not silently create a replacement account. No frontend deletion UI is included in this backend branch.
- No legal hold mechanism is implemented. Obtain appropriate advice for any actual preservation obligation before operational handling of such a case; do not invent a routine retention exception contrary to the selected deletion behavior.
