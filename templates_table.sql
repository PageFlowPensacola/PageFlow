CREATE TABLE templates (
	id SERIAL PRIMARY KEY,
	name varchar NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
	primary_org_id bigint NOT NULL,
	page_count smallint
);

CREATE TABLE template_pages (
	template_id int NOT NULL REFERENCES templates ON DELETE CASCADE,
	page_number smallint NOT NULL,
	page_data BYTEA NOT NULL,
	pxleft smallint,
	pxtop smallint,
	pxright smallint,
	pxbottom smallint,
	PRIMARY KEY (template_id, page_number)
);

CREATE TABLE template_signatories (
	id BIGSERIAL PRIMARY KEY,
	name varchar NOT NULL,
	template_id int NOT NULL REFERENCES templates ON DELETE CASCADE
);

CREATE TABLE audit_rects (
	id BIGSERIAL PRIMARY KEY,
	audit_type varchar NOT NULL, -- NOT IN USE initials, signature, date
	template_id int NOT NULL REFERENCES templates ON DELETE CASCADE,
	page_number smallint NOT NULL,
	x1 double precision NOT NULL,
	y1 double precision NOT NULL,
	x2 double precision NOT NULL,
	y2 double precision NOT NULL,
	name varchar DEFAULT NULL,
	-- ALTER table audit_rects add column transition_score int NOT NULL DEFAULT -1
	transition_score int NOT NULL DEFAULT -1, -- to compare against signature
	template_signatory_id int REFERENCES template_signatories ON DELETE CASCADE
);
