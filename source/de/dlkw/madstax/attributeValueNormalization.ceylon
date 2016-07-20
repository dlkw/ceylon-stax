class NState of simple
        | reference
{
    String s;

    shared new simple{s="simple";}
    shared new reference{s="reference";}

    shared actual String string => s;
}

Map<String, String> predefinedEntities = map({
        "amp"  -> "&#38;",
        "lt"   -> "&#60;",
        "gt"   -> ">",
        "apos" -> "'",
        "quot" -> "\""
});

String normalizeAttributeValue(String unnormalized, Boolean cdata)
{
    value replaced = replaceReference(unnormalized);
    
    if (cdata) {
        return replaced;
    }
    else {
        return trimAndCollateWhitespace(replaced);
    }
}

String trimAndCollateWhitespace(String input)
{
    variable Boolean before = true;
    variable Integer wsCount = 0;
    value builder = StringBuilder();
    for (c in input) {
        if (c == ' ') {
            if (!before) {
                ++wsCount;
            }
        }
        else {
            if (wsCount > 0) {
                for (i in 0:wsCount) {
                    builder.appendCharacter(' ');
                }
                wsCount = 0;
            }
            builder.appendCharacter(c);
        }
    }
    return builder.string;
}

String gatherReference(Character|Finished nextChar(), Character? first = null)
{
    StringBuilder sb = StringBuilder();
    if (exists first) {
        sb.appendCharacter(first);
    }
    
    while (true) {
        value c = nextChar();
        
        if (!is Finished c) {
            if (c == ';') {
                return sb.string;
            }
            if (isChar(c)) {
                sb.appendCharacter(c);
            }
            else {
                throw ParseException("invalid character in reference");
            }
        }
        else {
            throw ParseException("EOF in reference");
        }
    }
}

Character resolveCharacterReference(Character|Finished nextChar())
{
    if (!is Finished c0 = nextChar()) {
        Integer? code;
        if (c0 == 'x') {
            value reference = gatherReference(nextChar);
            
            code = parseInteger(reference, 16);
        }
        else {
            value reference = gatherReference(nextChar, c0);
            
            code = parseInteger(reference);
        }
        
        if (exists code) {
            value char = code.character;
            if (!isChar(char)) {
                throw ParseException("character reference for invalid character");
            }
            return code.character;
        }
        else {
            throw ParseException("invalid character reference");
        }
    }
    else {
        throw ParseException("EOF in character reference");
    }
}

String replaceReference(String input)
{
    value iterator = input.iterator();

    value builder = StringBuilder();
    variable value state = NState.simple;
    
    while (true) {
        switch(state)
        case (NState.simple) {
            if (!is Finished c = iterator.next()) {
                if (isXmlWhitespace(c)) {
                    builder.appendCharacter('\{#20}');
                }
                else if (c == '&') {
                    state = NState.reference;
                }
                else {
                    builder.appendCharacter(c);
                }
            }
            else {
                return builder.string;
            }
        }
        
        case (NState.reference) {
            if (!is Finished c = iterator.next()) {
                if (c == '#') {
                    value cr = resolveCharacterReference(iterator.next);
                    builder.appendCharacter(cr);
                    state = NState.simple;
                }
                else {
                    value reference = gatherReference(iterator.next, c);
                    
                    value replacement = predefinedEntities[reference];
                    if (exists replacement) {
                        if (replacement.any((c) => c == '<')) {
                            throw ParseException("illegale tag start in attribute value");
                        }
                        value rep = replaceReference(replacement);
                        builder.append(rep);
                        state = NState.simple;
                    }
                    else {
                        throw ParseException("undefined entity ``reference``");
                    }
                }
            }
            else {
                throw ParseException("EOF in reference");
            }
        }
    }
}