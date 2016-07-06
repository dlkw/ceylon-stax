shared class PositionPushbackSource(Iterator<Character> input)
{
    variable Integer _offset = 0;
    variable Integer _line = 1;
    variable Integer _column = 0;
    variable Integer prevColumn = -1;
    
    shared Integer offset => _offset;
    shared Integer line => if (_column == 0) then _line - 1 else _line;
    shared Integer column =>if (_column == 0) then prevColumn + 1 else _column;

    variable Character[] nnx = [];

    shared void pushbackChar(Character c)
    {
        nnx = nnx.withLeading(c);
        --_offset;
        if (c == '\{#0a}') {
            --_line;
        }
        // column will be wrong after pushing back a linefeed character
        // until a subsequent nextChar() will return a linefeed 
        --_column;
    }
    
    shared Character|Finished nextChar()
    {
        Character|Finished rawNextChar()
        {
            if (exists c = nnx.first) {
                nnx = nnx.rest;
                ++_offset;
                return c;
            }
            // offset will be wrong after reading from a finished
            // iterable, but never mind, save the type check
                    ++_offset;
            return input.next();
        }
        
        value c = rawNextChar();
        if (is Finished c) {
            return c;
        }
        
        if (c == '\{#0a}') {
            ++_line;
            prevColumn = _column;
            _column = 0;
            return c;
        }
        
        if (c == '\{#0d}') {
            value c1 = rawNextChar();
            if (is Finished c1) {
                ++_line;
                prevColumn = _column;
                _column = 0;
                return '\{#0a}';
            }
            if (c1 == '\{#0a}') {
                ++_line;
                prevColumn = _column;
                _column = 0;
                return '\{#0a}';
            }
            // save the column must be done before pushback
            prevColumn = _column;
            pushbackChar(c1);
            ++_line;
            _column = 0;
            return '\{#0a}';
        }
        
                ++_column;
        return c;
    }
}