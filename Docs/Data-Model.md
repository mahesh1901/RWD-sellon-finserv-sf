Account (Standard)
  └── [Lookup]       Loan_Application__c
        ├── [MD]     Applicant__c            (cascade delete)
        ├── [MD]     Co_Applicant__c         (cascade delete)
        ├── [MD]     Document__c             (cascade delete)
        ├── [Lookup] Property__c             (retained)
        ├── [Lookup] Credit_Check__c         (retained — compliance)
        ├── [Lookup] Loan_Disbursement__c    (retained — finance audit)
        └── [Lookup] Verification_Log__c     (retained — compliance)

Audit_Log__c   — standalone, no parent, without sharing
Lead           — standard, converts to Account + Contact + Opportunity
Case           — standard, linked to Account