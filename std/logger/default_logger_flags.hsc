package logger

DefaultLoggerFlag :: distinct alias uint

DEFAULT_LOGGER_FLAG_DATE      : DefaultLoggerFlag : 1 << 0
DEFAULT_LOGGER_FLAG_TIME      : DefaultLoggerFlag : 1 << 1
DEFAULT_LOGGER_FLAG_FILE_PATH : DefaultLoggerFlag : 1 << 2
DEFAULT_LOGGER_FLAG_FILE_NAME : DefaultLoggerFlag : 1 << 3
DEFAULT_LOGGER_FLAG_LINE      : DefaultLoggerFlag : 1 << 4
DEFAULT_LOGGER_FLAG_FUNCTION  : DefaultLoggerFlag : 1 << 5
DEFAULT_LOGGER_FLAG_THREAD_ID : DefaultLoggerFlag : 1 << 6

DEFAULT_LOGGER_FLAG_DEFAULT : DefaultLoggerFlag : DEFAULT_LOGGER_FLAG_DATE 
                                                | DEFAULT_LOGGER_FLAG_TIME
                                                | DEFAULT_LOGGER_FLAG_FILE_NAME
                                                | DEFAULT_LOGGER_FLAG_LINE
                                                | DEFAULT_LOGGER_FLAG_FUNCTION
                                                | DEFAULT_LOGGER_FLAG_THREAD_ID
