# PowerShell session comparison

## Snapshot metadata

- reference: schema 1, discovery policy 1, redaction HMAC-SHA256 v1, keyId 567777d6d870567a0a7488fe949a4092b967ce9a61d801b0e8fadfab3e966f17
- difference: schema 1, discovery policy 1, redaction HMAC-SHA256 v1, keyId 567777d6d870567a0a7488fe949a4092b967ce9a61d801b0e8fadfab3e966f17

## Summary

Overall: Confirmed difference. Confirmed differences: 2; No observed differences: 7; Unable to determine: 1.

## Confirmed difference

- powerShellVersion: The recorded values differ under this comparison policy. (ValuesDifferent)
  - Reference: 7.6.5
  - Difference: 7.6.4

## No observed difference

- workingDirectory: The recorded values are equal under this comparison policy. (ValuesEqual)
- psModulePath: Both observations explicitly record absence. (BothAbsent)
- pathExt: The recorded values are equal under this comparison policy. (ValuesEqual)
- moduleAutoLoadingPreference: The recorded values are equal under this comparison policy. (ValuesEqual)

## Unable to determine

- path: At least one observation is incomplete. (ObservationUnknown)
  - Reference: Confirmed observation; Difference: Unable to determine / EnvironmentReadFailed.

## Command observations

### Query 7180b5f042fbab1e234209ac58ae449e95746ce8366b5f03f754e1845c27b9c3

Captured occurrences: reference 1, difference 1.

- internalCandidates: No observed difference — Both observations explicitly record absence. (BothAbsent)
- externalCandidates: Confirmed difference — The recorded values differ under this comparison policy. (ValuesDifferent)
  - referenceOnly, count 1: type=Application; name=1e62a4db7ddba5a951f02dd710523bcef10ee87a9098b204b281c6bff7a7bfc1; path=e0064f67a5df0d8d14738d5d41876831c3201341f76c4b659b2c02d645d73247
  - differenceOnly, count 1: type=Application; name=1e62a4db7ddba5a951f02dd710523bcef10ee87a9098b204b281c6bff7a7bfc1; path=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- aliases: No observed difference — Both observations explicitly record absence. (BothAbsent)
- functions: No observed difference — Both observations explicitly record absence. (BothAbsent)

## Privacy and limitations

- Differences are observations, not proof of causation.
- Candidate-only policy: no execution winner is inferred.
- Query identities are case-sensitive input HMACs in snapshot schema 1. Unmatched queries are not candidate differences.
- Presence and absence can be compared without comparing private values. Unpaired queries cannot be associated across incompatible keys.