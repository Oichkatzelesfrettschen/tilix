module pured.terminal.search_history;

version (PURE_D_BACKEND):

struct SearchHistory {
    string[] entries;
    int index = -1;
    string draft;
    size_t maxEntries = 50;

    void resetDraft(string value) {
        draft = value;
        index = cast(int)entries.length;
    }

    void updateDraft(string value) {
        draft = value;
        index = cast(int)entries.length;
    }

    void push(string query) {
        if (query.length == 0) {
            return;
        }
        if (entries.length != 0 && entries[$ - 1] == query) {
            return;
        }
        entries ~= query;
        if (entries.length > maxEntries) {
            auto start = entries.length - maxEntries;
            entries = entries[start .. $];
        }
        index = cast(int)entries.length;
    }

    string prev(string current) {
        if (entries.length == 0) {
            return current;
        }
        if (index < 0) {
            index = cast(int)entries.length;
        }
        if (index == cast(int)entries.length) {
            draft = current;
        }
        if (index > 0) {
            index--;
        }
        return entries[index];
    }

    string next() {
        if (entries.length == 0) {
            return draft;
        }
        if (index < cast(int)entries.length) {
            index++;
            if (index >= cast(int)entries.length) {
                index = cast(int)entries.length;
                return draft;
            }
            return entries[index];
        }
        return draft;
    }
}
