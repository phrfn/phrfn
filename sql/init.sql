use phr;

insert into users(status,email,firstName,lastName,password,created) values('Active', 'evanwrichardson@gmail.com', 'Evan', 'Richardson', "oos!IeCh", now());
select @user_id := last_insert_id();

insert into ehr_entities(name,displayname,ehrType,url,status,created) values('PAMF', 'Palo Alto Medical Foundation', 'Provider', 'https://myhealthonline.sutterhealth.org/mho/default.asp', 'A', now());
insert into user_has_these_ehrs(userId,ehrEntityId,ehrUserId,ehrEmail,ehrPassword,created) values(@user_id, last_insert_id(),'evanwrichardson@gmail.com','evanwrichardson@gmail.com','Nav33nSax',now());

insert into ehr_entities(name,displayname,ehrType,url,status,created) values('Stanford', 'Stanford Medicine', 'Hospital', 'https://myhealth.stanfordmedicine.org/myhealth/', 'A',now());
insert into user_has_these_ehrs(userId,ehrEntityId,ehrUserId,ehrEmail,ehrPassword,created) values(@user_id, last_insert_id(), 'evanwrichardson@gmail.com','evanwrichardson@gmail.com','Nav33nSax',now());

