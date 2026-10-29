# Tenora Household

Tenora models collaboration among authenticated adults while keeping each adult's personal productivity information private.

## Language

**Household Owner**:
The single active household member who holds final administrative responsibility for the household.
_Avoid_: Primary admin, co-owner

**Ownership Transfer**:
A change of household ownership initiated by the current Household Owner and completed only after an eligible recipient explicitly accepts it. Once completed, the former owner becomes an Adult Member.
_Avoid_: Owner reassignment, ownership takeover

**Ownership Recipient**:
An active Adult Member or Household Admin selected to receive ownership.
_Avoid_: Successor, invitee

**Pending Ownership Transfer**:
The single outstanding request for an Ownership Recipient to accept ownership. It is visible only to the Household Owner and recipient, expires after one week, and may end earlier when the owner cancels it or the recipient declines it.
_Avoid_: Pending promotion, owner invitation

**Member Name**:
An account-level preferred name displayed only to fellow household members so they can identify one another. It is required when creating a household or accepting an invitation, and must be distinguishable within that household.
_Avoid_: Account email, member ID

**Ownership Transfer History**:
The immutable household record of ownership requests being created, cancelled, declined, expired, or accepted.
_Avoid_: Transfer log, notification history

**Household Admin**:
An active adult member with delegated household-management authority but no ownership or access to another adult's private information.
_Avoid_: Co-owner, super user

**Adult Member**:
An authenticated adult who actively belongs to the household without ownership or administrative authority.
_Avoid_: Dependent, user
