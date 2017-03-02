--
-- Table structure for table 'oai_harvester_biblios'
--

CREATE TABLE IF NOT EXISTS `oai_harvester_biblios` (
  `import_oai_biblio_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `oai_repository` varchar(255) COLLATE utf8_unicode_ci NOT NULL,
  `oai_identifier` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `biblionumber` int(11) NOT NULL,
  PRIMARY KEY (`import_oai_biblio_id`),
  UNIQUE KEY `oai_record` (`oai_identifier`,`oai_repository`) USING BTREE,
  KEY `FK_import_oai_biblio_1` (`biblionumber`),
  CONSTRAINT `FK_import_oai_biblio_1` FOREIGN KEY (`biblionumber`) REFERENCES `biblio` (`biblionumber`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Table structure for table 'oai_harvester_history'
--

CREATE TABLE IF NOT EXISTS  `oai_harvester_history` (
  `import_oai_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `repository` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `header_identifier` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `header_datestamp` datetime NOT NULL,
  `header_status` varchar(45) COLLATE utf8_unicode_ci DEFAULT NULL,
  `record` longtext COLLATE utf8_unicode_ci NOT NULL,
  `upload_timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `status` varchar(45) COLLATE utf8_unicode_ci NOT NULL,
  `filter` text COLLATE utf8_unicode_ci NOT NULL,
  `framework` varchar(4) COLLATE utf8_unicode_ci NOT NULL,
  `record_type` enum('biblio','auth','holdings') COLLATE utf8_unicode_ci NOT NULL,
  `matcher_code` varchar(10) COLLATE utf8_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`import_oai_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Table structure for table 'oai_harvester_import_queue'
--

CREATE TABLE IF NOT EXISTS `oai_harvester_import_queue` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `uuid` varchar(45) CHARACTER SET utf8 NOT NULL,
  `status` varchar(45) CHARACTER SET utf8 NOT NULL DEFAULT 'new',
  `result` text CHARACTER SET utf8 NOT NULL,
  `result_timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Table structure for table 'oai_harvester_requests'
--

CREATE TABLE IF NOT EXISTS `oai_harvester_requests` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `uuid` varchar(45) NOT NULL,
  `oai_verb` varchar(45) NOT NULL,
  `oai_metadataPrefix` varchar(255) NOT NULL,
  `oai_identifier` varchar(255) DEFAULT NULL,
  `oai_from` varchar(45) DEFAULT NULL,
  `oai_until` varchar(45) DEFAULT NULL,
  `oai_set` varchar(255) DEFAULT NULL,
  `http_url` varchar(255) DEFAULT NULL,
  `http_username` varchar(255) DEFAULT NULL,
  `http_password` varchar(255) DEFAULT NULL,
  `http_realm` varchar(255) DEFAULT NULL,
  `import_filter` varchar(255) NOT NULL,
  `import_framework_code` varchar(4) NOT NULL,
  `import_record_type` enum('biblio','auth','holdings') NOT NULL,
  `import_matcher_code` varchar(10) DEFAULT NULL,
  `interval` int(10) unsigned NOT NULL,
  `name` varchar(45) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
