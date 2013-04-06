create database if not exists phr;
use phr;

/* 
   User table. Every user who uses the system will have an entry here. User status can be 'Active' when a user registers, 
   or 'Inactive' or 'Deleted' if a request to terminate a user is received. Primary subscribers can exist in this table as
   'Inactive' if they have not registered. This can happen if for example a user who registers for the app is a dependent.
   The system will create an account for this user and then later as part of crawling also create the account of the primary
   subscriber but mark them as 'Inactive'. The relationship between the 'Active' user and the primary subscriber who is marked
   as 'Inactive' is maintained in the "user_has_these_plans" table where the "primarySubscriberId' is a foreign key that references
   the "users" table.

   Several other attributes will be ultimately added to this table but the ones that are absolutely required for the purpose of the
   prototype are: email, firstName, lastName, and password.
 */

CREATE TABLE IF NOT EXISTS users (
  id bigint unsigned NOT NULL auto_increment,
  status enum('Active','Inactive','Deleted') default NULL,
  email varchar(50) NOT NULL,
  emailHash varchar(50) NOT NULL,
  firstName varchar(50) NULL,
  lastName varchar(50) NULL,
  password varchar(50) NOT NULL,
  photo varchar(255) default NULL,
  address1 varchar(50) default NULL,
  address2 varchar(50) default NULL,
  city varchar(20) default NULL,
  state varchar(20) default NULL,
  zipCode varchar(10) default NULL,
  timeZone varchar(20) default NULL,
  updated timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  created TIMESTAMP NOT NULL,
  UNIQUE(email),
  PRIMARY KEY  (id)
) ENGINE=InnoDB;

/*
  An entry is added to the "providers" table by the crawlers for claims as well as the crawlers for EHR.

  The crawler for claims will add an entry to this table when crawling for claims. The provider name is on the claim detail page.

  The crawler for the EHR will add entries for providers in this table while crawling for tests, test_components, visit_details, surgeries
  and referrals. The referrals are crawled from the visit detail page of a visit at least within the PAMF EHR.
 */

CREATE TABLE IF NOT EXISTS providers (
  id bigint unsigned NOT NULL auto_increment,
  status enum('A','N','D') default NULL,
/*
  email varchar(50) NOT NULL,
  emailHash varchar(50) NOT NULL,
*/
  email varchar(50) default NULL,
  emailHash varchar(50) default NULL,
  firstName varchar(50) NULL,
  lastName varchar(50) NULL,
  fullName varchar(100) NOT NULL,
  photo varchar(255) default NULL,
  address1 varchar(50) default NULL,
  address2 varchar(50) default NULL,
  city varchar(20) default NULL,
  state varchar(20) default NULL,
  zipCode varchar(10) default NULL,
  timeZone varchar(20) default NULL,
  updated timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  created TIMESTAMP NOT NULL,
  UNIQUE(fullName),
  PRIMARY KEY  (id)
) ENGINE=InnoDB;



/*
  This table is populated by hand while adding each EHR source in the system. For the sake of our prototype, the following 4 EHRs will have records here:
     1. PAMF
     2. Stanford Medical
     3. Blue Shielf of CA
     4. Practice Fusion
*/

CREATE TABLE IF NOT EXISTS ehr_entities (
  id int unsigned NOT NULL auto_increment,
  name varchar(50) NOT NULL,
  displayName varchar(50) NOT NULL,
  ehrType enum('Hospital', 'Practice', 'Provider', 'Payer', 'DNA'),
  url varchar(256) NOT NULL,
  status enum('A', 'N'),
  updated timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  created TIMESTAMP NOT NULL,
  UNIQUE(name),
  PRIMARY KEY (id)
) ENGINE=InnoDB;



/*
  This table is populated during the registration process as the user adds account information for each EHR that he or she has account at.

  In the first pass, we will only populate ehrUserId, ehrPassword. Then at the time of the crawl we will populate the crawler will populate
  memberNumber and groupNumber fields appropriately.
*/

CREATE TABLE IF NOT EXISTS user_has_these_ehrs (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  memberNumber varchar(50) NULL,
  groupNumber varchar(50) NULL,
  status enum('Active', 'Inactive', 'Changed'),
  inactiveReason varchar(50) NULL,
  startDate TIMESTAMP NULL,
  endDate TIMESTAMP NULL,
  ehrUserId varchar(50) NOT NULL,
  ehrPassword varchar(50) NOT NULL,
  ehrEmail varchar(50) DEFAULT NULL,
  firstNameForEhr varchar(50) DEFAULT NULL,
  lastNameForEhr varchar(50) DEFAULT NULL,
  address1ForEhr varchar(50) DEFAULT NULL,
  address2ForEhr varchar(50) DEFAULT NULL,
  cityForEhr varchar(50) DEFAULT NULL,
  stateForEhr varchar(50) DEFAULT NULL,
  zipCodeForEhr varchar(50) DEFAULT NULL,
  updated timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  created TIMESTAMP NOT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


/*
  The claims crawler will create an entry in this table for each new plan that it comes across while crawling for a user's claims.
  For people who do not understand it, the word plan is used to describe the various kinds of plans that insurers offer. Plans have
  different characteristics such as different individual and family deductibles, different copays for RX, different co-insurance etc.
  
  The plan information can be scraped by visiting the "View Plan Summary" link on the home page. The member number and group number
  need to be populated in teh user_has_these_ehrs table and not in the plan_entities table.

  Generally the term copay is used for a fixed payment that a consumer must make when visiting a doctor or buying a drug. Someplans only
  have a copay. Increasingly many plans have a co-insurance as well on top of the copy. The co-insurance is typically a percentage value.
  Several attributes below are named as copayPercentage... etc. when they should actually be coinsurancePercentage.... etc. The Blue Shield
  of CA website calls them as such and I have tried to keep things simple.

  Here are the definitions of the various components:
     1.  copayPercentageOfficeVisits:  This is the co-insurance percentage for office visits and is typically ranges from 10-30%
     2.  copayPercentageForGenericRX:  This is the co-insurance percentage for Generic drugs
     3.  copayPercentageForBrandedRX:  This is the co-insurance percentage for Brandex drugs
     4.  copayPercentageforNonFormularyRX: A formulary is the list of drugs that are supported by a health plan. Non-formulary drugs 
                                           have higher copays and co-insurance.
     5.  maxCopayForInNetworkProviders: Most plans have an upper limit for the total amount of co-pay and co-insurance a consumer must bear.
                                        This value is for seeing in-network providers. Think of this as a maximum out of pocket (OOP) that a
                                        consumer might bear. There is a separate max value for out-of-network providers (below).
     6.  maxCopayForOutNetworkProviders: Maximum OOP for out-of-network providers 
     7.  maxDeductibleForInNetworkProviders: A deductible is an amount that the consumer must bear before the insurance kicks in (or before the
                                             co-insurance kicks in. This is the maximum deductible that a consumer must bear for seeing
                                             in-network providers. A deductible is upfront cost. The OOP above includes both the deductible and
                                             the co-insurance.
     8.  maxDeductibleForOutNetworkProviders: Deductible for seeing out-of-network providers
     9.  inNetworkDeductibleUsed: This is the current value of the deductible that the consumer has incurred out of the maxmimum deductible for in-network. 
                                  This will not be scraped presently because the Blue Shield of CA website does not provide this.
    10.  outOfNetworkDeductibleUsed: This is the current value of the deductible that a consumer has incurred for seeing out-of-network providers.
                                     This will not be scraped presently because the Blue Shield of CA website does not provide this.
    11.  maxInNetworkOOPUsed: This is the current value of the OOP incurred by a consumer for seeing in-network providers. This will not be scraped presently
                              because the Blue Shield of CA website does not provide this.
    12.  maxOutOfNetworkOOPUsed: This is the current value of the OOP incurred by a consumer for seeing out-of-network providers. This will not be scraped presently
                                 because the Blue Shield of CA website does not provide this.

  The planYear attribute does not need to be populated for now
*/

CREATE TABLE IF NOT EXISTS plan_entities (
  id bigint unsigned NOT NULL auto_increment,
  name varchar(50) NOT NULL,
  displayName varchar(50) NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  planYear varchar(10) NOT NULL,
  copayPercentageOfficeVisits decimal(5,2),
  copayPercentageForGenericRX decimal(5,2),
  copayPercentageForBrandedRX decimal(5,2),
  copayPercentageforNonFormularyRX decimal(5,2),
  maxCopayForInNetworkProviders decimal(12,2) NULL,
  maxCopayForOutNetworkProviders decimal(12,2) NULL,
  maxDeductibleForInNetworkProviders decimal(12,2) NULL,
  maxDeductibleForOutNetworkProviders decimal(12,2) NULL,
  inNetworkDeductibleUsed decimal(12,2) NULL,
  outOfNetworkDeductibleUsed decimal(12,2) NULL,
  maxInNetworkOOPUsed decimal(12,2) NULL,
  maxOutOfNetworkOOPUsed decimal(12,2) NULL,
  status enum('A', 'N') DEFAULT 'A',
  updated timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  created TIMESTAMP NOT NULL,
  foreign key (ehrEntityId) references ehr_entities(id),
  PRIMARY KEY (id)  
) ENGINE=InnoDB;


/*
  For each user, the claims crawler will also add an entry in this table if the relationship does not already exist. The primarySubscriberId
  and primarySubscriberNumber attribute will be updated only when crawling the claims details and will be updated one time only.

  Each user_claim record will also store the primarySubscriberNumber and primarySubscriberId attribute as well. But if these are not populated in
  the user_has_these_plans table then the corresponding record will also be updated with this information.

  Typically before updating the user_has_these_plans table with the primarySubscriber's information, the code must also add a record to the "users" table
  for the primary subscriber and mark the record as "Inactive". Later this information will be used to build a dependent relationship between the actual user
  and the primary subscriber such as "spouse", "child" etc. - But for later.
*/

CREATE TABLE IF NOT EXISTS user_has_these_plans (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  planEntityId bigint unsigned NOT NULL,
  status enum('A', 'N', 'C') DEFAULT 'A',
  inactiveReason varchar(50) NULL,
  memberNumber varchar(50) NULL,
  primarySubscriberId bigint unsigned NULL,
  primarySubscriberNumber varchar(50) NULL,
  startDate TIMESTAMP NULL,
  endDate TIMESTAMP NULL,
  updated timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  created TIMESTAMP NOT NULL,
  foreign key (userId) references users(id),
  foreign key (primarySubscriberId) references users(id),
  foreign key (planEntityId) references plan_entities(id),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


/*
  Populating records in this table is simple and straightforward. Records will be populated by the claims crawler.
  The only trickiness is to also populate the providerId and providerName. But those should be done only after adding a record
  to the "providers" table first if a record for that provider does not already exist in the "providers" table.

  No need to fill the "allowedAmount" because it is not available as a crawlable value. It can be computed but let us forego it.
  Also, fill the copay/consinsurance value in just the coInsurance attribute and leave the copay value as NULL.
 */

CREATE TABLE IF NOT EXISTS user_claims (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  planId bigint unsigned NOT NULL,
  claimNumber varchar(50) DEFAULT NULL,
  memberNumber varchar(50) DEFAULT NULL,
  primarySubscriberId bigint unsigned NULL,
  primarySubscriberNumber varchar(50) DEFAULT NULL,
  processedDate date DEFAULT NULL,
  providerId bigint unsigned DEFAULT NULL,
  providerName varchar(50) DEFAULT NULL,
  status varchar(20) DEFAULT NULL,
  serviceBeginDate date DEFAULT NULL,
  serviceEndDate date DEFAULT NULL,
  receivedDate date DEFAULT NULL,
  billedAmount decimal(18,2) DEFAULT NULL,
  allowedAmount decimal(18,2) DEFAULT NULL,
  paymentAmount decimal(18,2) DEFAULT NULL,
  deductibleAmount decimal(18,2) DEFAULT NULL,
  notCoveredAmount decimal(18,2) DEFAULT NULL,
  coInsurance decimal(18,2) DEFAULT NULL,
  coPay decimal(18,2) DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (planId) references user_has_these_plans(id),
  foreign key (primarySubscriberId) references users(id),
  foreign key (providerId) references providers(id),
  PRIMARY KEY (id)
) ENGINE=InnoDB;




CREATE TABLE IF NOT EXISTS remark_codes (
  id bigint unsigned NOT NULL auto_increment,
  ehrEntityId int unsigned NOT NULL,
  remarkCodeNumber varchar(10) DEFAULT NULL,
  remarkCodeDescription varchar(100) DEFAULT NULL,
  foreign key (ehrEntityId) references ehr_entities(id),
  PRIMARY KEY (id)
) ENGINE=InnoDB;



CREATE TABLE IF NOT EXISTS procedure_codes (
  id bigint unsigned NOT NULL auto_increment,
  procedureCodeNumber varchar(20)DEFAULT NULL,
  procedureDescription varchar(100) DEFAULT NULL,
  PRIMARY KEY(id)
) ENGINE=InnoDB;

/*
  Populating records in this table is simple and straightforward. Records will be populated by the claims crawler.

  "allowedAmount" must also be populated at the line item level. Also, fill the copay/consinsurance value in just the 
  coInsurance attribute and leave the copay value as NULL.

  Don't bother populating "remarkCodeId". Just populate the remarkCodeNumber. We will currently not use the "remark_codes" table
 */

CREATE TABLE IF NOT EXISTS claim_line_items (
  id bigint unsigned NOT NULL auto_increment,
  claimId bigint unsigned NOT NULL,
  procedureCodeId bigint unsigned DEFAULT NULL,
  procedureName varchar(100) DEFAULT NULL,
  serviceDate date DEFAULT NULL,
  billedAmount decimal(18,2) DEFAULT NULL,
  allowedAmount decimal(18,2) DEFAULT NULL,
  paymentAmount decimal(18,2) DEFAULT NULL,
  deductibleAmount decimal(18,2) DEFAULT NULL,
  notCoveredAmount decimal(18,2) DEFAULT NULL,
  coInsuranceAmount decimal(18,2) DEFAULT NULL,
  coPayamount decimal(18,2) DEFAULT NULL,
  remarkCodeId bigint unsigned DEFAULT NULL,
  remarkCodeNumber varchar(10) DEFAULT NULL,
  foreign key (claimId) references user_claims(id),
  foreign key (remarkCodeId) references remark_codes(id),
  foreign key (procedureCodeId) references procedure_codes(id),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


/*
  Currently to be populated only by the PAMF crawler. Go to the "Health Reminders" page from the left hand Nav bar.
  This should be self-explanatory.
*/


CREATE TABLE IF NOT EXISTS user_health_reminders (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  reminderName varchar(100) DEFAULT NULL,
  dueDateOrTimeFrame varchar(20) DEFAULT NULL,
  doneDate date DEFAULT NULL,
  status varchar(20) DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  UNIQUE(userId, ehrEntityId, reminderName,dueDateOrTimeFrame),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


/*
 Medication history, Allergies and Immunizations can all be populated by crawling the
    1. The Health Summary page on the Stanford website
    2. The Health Summary page on the PAMF website

 Or they can be crawled separately by visiting the medications, immunizations, and allergies pages from the left hand navigation bar
 for both the PAMF and Stanford website.

 The only trickiness is to first populate the "providers" table with an entry for the provider if it does not already exist before populating 
 the providerId in this table
*/


CREATE TABLE IF NOT EXISTS user_medication_history (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  medication varchar(100) DEFAULT NULL,
  genericname varchar(100) DEFAULT NULL,
  instructions varchar(100) DEFAULT NULL,
  prescribingProviderId bigint unsigned DEFAULT NULL,
  providerId bigint unsigned DEFAULT NULL,
  startDate date DEFAULT NULL,
  endDate date DEFAULT NULL,
  status varchar(20) DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (prescribingProviderId) references providers(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  foreign key (providerId) references providers(id),
  UNIQUE KEY medication_UNIQUE (userId, medication, startDate, endDate, ehrEntityId),
  PRIMARY KEY (id)
) ENGINE=InnoDB;



CREATE TABLE IF NOT EXISTS user_allergies (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  allergen varchar(50) DEFAULT NULL,
  reaction varchar(100) DEFAULT NULL,
  severity varchar(100) DEFAULT NULL,
  reportedDate date DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  UNIQUE KEY allergy_UNIQUE (userId, allergen, ehrEntityId),
  PRIMARY KEY (id)
) ENGINE=InnoDB;



CREATE TABLE IF NOT EXISTS user_immunizations (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  immunizationName varchar(50) DEFAULT NULL,
  dueDateOrTimeFrame varchar(20) DEFAULT NULL,
  doneDate date DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  UNIQUE(userId, ehrEntityId, immunizationName),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


/*
  Visit the "Medical History" page from the left hand nav bar for both PAMF and Stanford sites.

  There are multiple sections in the history page such as:
    1. Diagnosis
    2. Surgial history
    3. Family Medical history
    4. Social history (does not exist in the Stanford website)
    5. Family Status (not populated in either Stanford or PAMF websites

  The family medical history has the history for parents currently. Just to model this appropriately, I have created an enum
  called relationship. The value of this enum by default is "Self" and will be used for populating records corresponding to sections
  Diagnosis, and  Surgical history.

  We will currently not populate "social history".

  Records for Family medical history will be populated appropriately with the value of the enum being either "Father" or "Mother" currently.

*/

CREATE TABLE IF NOT EXISTS user_medical_history (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  historyType enum('Medical', 'Surgical', 'Family'),
  relationship enum('Self', 'Father', 'Mother', 'Brother', 'Sister', 'identical twin', 'paternal uncle', 'paternal aunt', 'maternal uncle', 'maternal aunt', 'paternal grandfather', 'paternal grandmother', 'maternal grandfather', 'maternal grandmother') DEFAULT 'Self',
  diagnosis varchar(100) DEFAULT NULL,
  diagnosisDateOrTimeFrame varchar(20) DEFAULT NULL,
  comments varchar(256) DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  UNIQUE(userId, ehrEntityId, historyType, diagnosis),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


/*
  To be populated by the PAMF and Stanford crawlers after visiting the "Upcoming Appts" or "Upcoming Appointments" pages from the left hand navigation bar
 */

CREATE TABLE IF NOT EXISTS user_appointments (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  dueDate varchar(50) NOT NULL,
  description varchar(100) NOT NULL,
  location varchar(100) NOT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  UNIQUE(userId, ehrEntityId, dueDate, location),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


/*
  Populating records in the "user_tests" table is straightforward. Visit the "Test Results" page in the PAMF and Stanford websites to crawl the values for
  populating records in this table.

  The only trickiness is to first populate a record in the providers table for the provider who ordered the tests before populating the corresponding values
  in any record in this table
*/

CREATE TABLE IF NOT EXISTS user_tests (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  testName varchar(50) DEFAULT NULL,
  dateOrdered date DEFAULT NULL,
  providerId bigint unsigned DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  foreign key (providerId) references providers(id),
  UNIQUE KEY test_UNIQUE (userId, ehrEntityId, testName, providerId, dateOrdered),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


/*
  This is a tricky table to populate.

  I am currently assuming that there are two types of records to be populated in this table - "imaging" and "labs".

  The data that is captured for each of these record types is different and I have modelled it by having different attributes
  in this table but appropriately setting the testType enum.

  Question: how do we distinguish which test type is "lab" and which is "imaging"? 
  Answer: Normally this will be done by having a pre-populated table of all imaging and lab tests and matching the test name
          against this table. For now, we will indeed have this table called "labOrImaging" that will be populated with just
          the names of imaging tests that were done on Evan. If the tests match those then they will be imaging tests else 
          lab tests.

  For lab tests the following fields will be populated by crawling each test component. Notice that for each test component multiple
  records might be created because the EHR system records some details in a crazy way. I will explain later.
         1.  testComponentName
         2.  userValue of the test component
         3.  standardRange value
         4.  units
         5.  flags
         6.  testComponent Result
         7.  dateSpecimenCollected
         8.  dateResultProvided
         9.  orderingProviderName
        10.  providerId

   For imaging test the following fields will be populated:
         1.  testComponentName
         2.  imagingNarrative
         3.  imagingImpression
         4.  dateSpecimenCollected
         5.  dateResultProvided
         6.  orderingProviderName
         7.  providerId

*/

CREATE TABLE IF NOT EXISTS user_test_components (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  userTestId bigint unsigned NOT NULL,
  testType enum('lab', 'imaging'), -- imaging if name prefix is XR or CT
  testComponentName varchar(50) DEFAULT NULL, -- next 4 from one row in labdetail -> Component results (labdetal PAMF)
  userValue varchar(20) DEFAULT NULL,
  standardRange varchar(20) DEFAULT NULL,
  units varchar(20) DEFAULT NULL,
  flag varchar(20) DEFAULT NULL,
  testComponentResult varchar(100) DEFAULT NULL, -- row following the above row (PAMF)
  dateSpecimenCollected date DEFAULT NULL, -- labdetail PAMF
  dateResultProvided date DEFAULT NULL,    -- labdetail PAMF
  imagingNarrative varchar(1024) DEFAULT NULL, -- labdetail Stanford
  imagingImpression varchar(1024) DEFAULT NULL, -- labdetail Stanford
  -- orderingProviderName varchar(50) DEFAULT NULL, -- labdetail PAMF
  providerId bigint unsigned DEFAULT NULL, -- for the above orderingProviderName ??
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  foreign key (userTestId) references user_tests(id),
  foreign key (providerId) references providers(id),
  UNIQUE(userId, ehrEntityId, userTestId, testType, testComponentName),
  PRIMARY KEY (id)
) ENGINE=InnoDB;



/*
   the user_visits table will be populated by the PAMF and Stanford crawlers. Additional information about each visit is populated in these
   additional tables:
      1. user_visit_details
      2. user_visit_vitals
      3. user_visit_diagnosis
      4. user_visit_tests
      5. user_visit_referrals
      6. user_visit_surgeries

   Stanford crawlers need to crawl:
      1. Hospital Admissions page from the left hand nav bar. Unfortunately we can only pick up summary information such as
         hospital stay information and no other details for the hospital admissions are available. The value for "providerType"
         attribute for these records will be "inpatient"
      2. Past Clinic Visists and Contacts from the left hand nav bar. Entries from these pages will result in records in the 
         user_visits table with "providerType" as "outpatient" for now. They will also result in additional records to be inserted
         in the above mentioned 6 tables.

    PAMF crawler will need to crawl:
      1. After visit summary page from the left hand nav bar. This action will also result in entried being made in the above 
         mentioned 6 tables. Also the "providerType" will be "outpatient".


    Entries in the user_visits table are straightforward. The biggest trickiness is in populating entries in the above mentioned 6 tables.

*/




CREATE TABLE IF NOT EXISTS user_visits (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  description varchar(50) DEFAULT NULL,
  visitDateTime TIMESTAMP NULL,
  departmentOrClinic varchar(50) DEFAULT NULL,
  providerType enum ('outpatient', 'inpatient') DEFAULT 'outpatient',
  dischargeDateTime TIMESTAMP NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  UNIQUE KEY (userId, ehrEntityId, visitDateTime, departmentOrClinic),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


/*
   For Stanford crawler do the following:

      1. visit date, visit time, providerName are self-explnatory and can be easily found on the details page for the visit.
      2. providerId will be populated by first populating the provider record in the "providers" table.
      3. reasonForVisit: Populate this with the value of the "Department" on the details page
      4. visitType: will have the value next to the date and time below the patients name (Office Visit or Hospital Encounter"
      5. referrals and vitals will have the default value of 'N'
      6. testsOrdered will have the value of 'Y' if any tests were ordered. For e.g. in the case of Evan some of the detail pages
         have a section called "Lab and imaging Orders". If this section exists the value of testsOrdered would be 'Y' and the corresponding
         imaging test will be entered as a record in the "user_visit_tests" table.
      7. The value of the "surgery" attribute will be 'Y' if the "Surgery Information" section shows up in the details page as is the case with
         the visit on January 30 with Dr. Julius Anthony Bishop. Records with the details of the surgery will then be entered in the
         "user_visit_surgeries" table

    For PAMF crawler do the following:
      1. visit date, visit time, providerName are self-explnatory and can be easily found on the details page for the visit.
      2. providerId will be populated by first populating the provider record in the "providers" table.
      3. reasonForVisit: Populate this with the value of the "Reason For Visit" on the details page
      4. visitType: will have the value of "Visit Type" on the details page
      5. referrals will be populated with the value of 'Y' if the details page has any referrals under "Tests and/or treatments prescribed during the visit" as
         is the case on the details page for the visit corresponding to visit on December 19, 2011 with Catherine Marie Chin-Garcia. Records
         will be added to the "user_visit_referrals" table as well.
      6. vitals will be populated with the value of 'Y' if the "Vitals" section shows up on the details page as is the case on the details page for the 
         visit corresponding to visit on December 19, 2011 with Catherine Marie Chin-Garcia. Records will be added to the "user_visit_vitals" table as well.
      7. testsOrdered will have a value of 'Y' if the "Future Orders" section shows up on the details page as as is the case on the details page for the 
         visit corresponding to visit on December 19, 2011 with Catherine Marie Chin-Garcia. Records will be added to the "user_visit_tests" table as well.

         The thing that I really want to achieve is to also set up the relationship between the records in the "user_tests" table and tie them to the tests ordered
         during the visit. You can figure out how to do that or leave the "userTestId" field in the "user_visit_tests" table as NULL.

*/

CREATE TABLE IF NOT EXISTS user_visit_details (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  userVisitId bigint unsigned NOT NULL,
  visitTimestamp TIMESTAMP NOT NULL,
  -- visitDate varchar(20) DEFAULT NULL,
  -- visitTime varchar(20) DEFAULT NULL,
  -- providerName varchar(50) DEFAULT NULL,
  providerId bigint unsigned DEFAULT NULL,
  reasonForVisit varchar(50) DEFAULT NULL,
  visitType varchar(20) DEFAULT NULL,
  diagnosis enum('N', 'Y') DEFAULT 'N',
  vitals enum('N', 'Y') DEFAULT 'N',
  referrals enum('N', 'Y') DEFAULT 'N',
  testsOrdered enum('N', 'Y') DEFAULT 'N',
  surgery enum('N', 'Y') DEFAULT 'N',
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  foreign key (userVisitId) references user_visits(id),
  foreign key (providerId) references providers(id),
  UNIQUE(userId, ehrEntityId, userVisitId, visitTimestamp,providerId),
  PRIMARY KEY (id)
) ENGINE=InnoDB;



CREATE TABLE IF NOT EXISTS user_visit_diagnosis (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  visitDetailId bigint unsigned NOT NULL,
  description varchar(512) DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  foreign key (visitDetailId) references user_visit_details(id),
  UNIQUE(userId, ehrEntityId, visitDetailId, description),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


CREATE TABLE IF NOT EXISTS user_visit_vitals (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  visitDetailId bigint unsigned NOT NULL,
  vitalName varchar(50) DEFAULT NULL,
  vitalValue varchar(50) DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  foreign key (visitDetailId) references user_visit_details(id),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


CREATE TABLE IF NOT EXISTS user_visit_referrals (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  visitDetailId bigint unsigned NOT NULL,
  referredProviderId bigint unsigned DEFAULT NULL,
  referralInstructions varchar(512) DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  foreign key (visitDetailId) references user_visit_details(id),
  foreign key (referredProviderId) references providers(id),
  UNIQUE(userId,ehrEntityId,visitDetailId,referredProviderId),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


CREATE TABLE IF NOT EXISTS user_visit_tests (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  visitDetailId bigint unsigned NOT NULL,
  userTestId bigint unsigned DEFAULT NULL,
  -- testName varchar(50) DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  foreign key (visitDetailId) references user_visit_details(id),
  foreign key (userTestId) references user_tests(id),
  UNIQUE(userId, ehrEntityId, visitDetailId, userTestId),
  PRIMARY KEY (id)
) ENGINE=InnoDB;


CREATE TABLE IF NOT EXISTS user_visit_surgeries (
  id bigint unsigned NOT NULL auto_increment,
  userId bigint unsigned NOT NULL,
  ehrEntityId int unsigned NOT NULL,
  visitDetailId bigint unsigned NOT NULL,
  primaryProcedure varchar(100) DEFAULT NULL,
  dateTimePerformed datetime DEFAULT NULL,
  -- primarySurgeon varchar(50) DEFAULT NULL,
  providerId bigint unsigned DEFAULT NULL,
  location varchar(100) DEFAULT NULL,
  status varchar(20) DEFAULT NULL,
  foreign key (userId) references users(id),
  foreign key (ehrEntityId) references ehr_entities(id),
  foreign key (visitDetailId) references user_visit_details(id),
  foreign key (providerId) references providers(id),
  UNIQUE(userId, ehrEntityId, visitDetailId, primaryProcedure),
  PRIMARY KEY (id)
) ENGINE=InnoDB;

