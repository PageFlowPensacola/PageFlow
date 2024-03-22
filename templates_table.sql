CREATE TABLE templates (
	id SERIAL PRIMARY KEY,
	name varchar NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE template_pages (
	template_id int NOT NULL REFERENCES templates,
	page_number smallint NOT NULL,
	page_data BYTEA NOT NULL
);

-- TODO following two
CREATE TABLE `template_signatory` (
  `template_signatory_id` bigint(15) NOT NULL,
  `name` varchar(256) NOT NULL,
  `page_group_id` bigint(15) DEFAULT NULL,
  PRIMARY KEY (`template_signatory_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE `audit_rect` (
  `audit_rect_id` bigint(15) NOT NULL,
  `audit_type` varchar(45) NOT NULL,
  `x1` smallint(6) NOT NULL,
  `y1` smallint(6) NOT NULL,
  `x2` smallint(6) NOT NULL,
  `y2` smallint(6) NOT NULL,
  `page_type_id` bigint(15) NOT NULL,
  `name` varchar(256) DEFAULT NULL,
  `template_signatory_id` bigint(20) NOT NULL,
  PRIMARY KEY (`audit_rect_id`),
  KEY `fk_audit_rect_page_type1_idx` (`page_type_id`),
  CONSTRAINT `fk_audit_rect_page_type1` FOREIGN KEY (`page_type_id`) REFERENCES `page_type` (`page_type_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
