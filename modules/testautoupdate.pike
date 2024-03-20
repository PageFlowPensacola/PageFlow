// Test File System Events to auto update on file save
protected void create(string name){
	System.FSEvents.EventStream(
		G->bootstrap_files, 0.0625, System.FSEvents.kFSEventStreamEventIdSinceNow
	)->set_callback() {
		werror("FSEvent! %O\n", __ARGS__);
	};
}
