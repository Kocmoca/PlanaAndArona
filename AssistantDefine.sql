CREATE TABLE IF NOT EXISTS Kocmoca_Assistants
(
    'AssistantType'		TEXT NOT NULL,
    'Name'				TEXT,
    'Description'		TEXT,
    'Icon'				TEXT,
    'Portrait'			TEXT,
    'UnitType'			TEXT,
    'LeaderType'		TEXT,
    'TopicType'			TEXT,
    'SceneType'			TEXT,			--assistants assigned to same scene will be put together
    PRIMARY KEY(AssistantType)
);

CREATE TABLE IF NOT EXISTS Kocmoca_Assistant_Topics
(
    'ID'				INTEGER PRIMARY KEY AUTOINCREMENT,
    'TopicType'			TEXT NOT NULL,
    'TopicBranch'		TEXT
);
