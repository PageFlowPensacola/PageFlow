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
