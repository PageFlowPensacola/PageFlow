inherit annotated;

@export:
__async__ mapping|zero fetch_doc_package(int id) {
/* 	// ar.id will be the same as pr.audit_rect_id unless pr.audit_rect_id is null
	array(mapping) file_rects = await(G->G->DB->run_pg_query(#"
		SELECT ar.id as audit_rect_id, difference, template_id, page_number, ufp.file_id, ufp.seq_idx, audit_type, name, optional
		FROM uploaded_file_pages ufp
		LEFT JOIN audit_rects ar USING (template_id, page_number)
		LEFT JOIN page_rects pr ON pr.file_id = ufp.file_id AND pr.seq_idx = ufp.seq_idx AND pr.audit_rect_id = ar.id
		WHERE ufp.file_id = :id
		AND template_id IS NOT NULL
		ORDER BY ufp.file_id, ufp.seq_idx, ar.id
		", (["id": id])));
	mapping statuses = ([]);
	foreach(file_rects, mapping rect) {
		statuses[rect->template_id+":"+rect->page_number] = 1; // this one we indeed have
		// is there rect content?
		if (rect->audit_rect_id) {
			int signed = rect->difference || 0 >= 100 ;
			if (!signed && !rect->optional) {
				// statuses->missing += ({rect->audit_rect_id});
			}
			statuses[rect->audit_rect_id] = signed;
		}
	}
	return statuses; */

}

protected void foo(string name) {
			::create(name);
			foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
				if (ann)
					foreach (indices(ann), mixed anno) {
						if (functionp(anno)) anno(this, name, key);
					}
			}
}
