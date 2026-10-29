---
status: accepted
---

# Use a consensual single-owner household transfer

Tenora households have exactly one Household Owner. Only that owner may request transfer to one active Adult Member or Household Admin, only one request may be pending, and ownership changes only when the recipient explicitly accepts within one week. The former owner remains as an Adult Member; the owner may cancel, the recipient may decline, and the first committed action wins under concurrency. This preserves clear responsibility without allowing surprise promotion, admin takeover, or unilateral loss of another adult's access.

Member Names are required before household creation or invitation acceptance and must be distinguishable within a household, because ownership cannot safely be transferred among anonymous “Adult member” rows. Pending requests are visible only to the owner and recipient; every lifecycle transition is retained in immutable household history. In-app notification ships with the transfer flow, while server-driven APNs delivery remains a follow-up because Tenora does not yet have remote push infrastructure.
