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
        "quot" -> "\"",
        "ga"-> "aha<joi>mama</joi> ",
        "nana"->"a&amp;uu&lt;zz"
});

String|ParseError normalizeAttributeValue(String unnormalized, Boolean cdata)
{
    value replaced = replaceReference(unnormalized);
    if (is ParseError replaced) {
        return replaced;
    }
    
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

String|ParseError gatherReference(Character|Finished nextChar(), Character? first = null)
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
                return ParseError("invalid character in reference");
            }
        }
        else {
            return ParseError("EOF in reference");
        }
    }
}

Character|ParseError resolveCharacterReference(Character|Finished nextChar())
{
    if (!is Finished c0 = nextChar()) {
        Integer? code;
        if (c0 == 'x') {
            value reference = gatherReference(nextChar);
            if (is ParseError reference) {
                return reference;
            }
            
            code = parseInteger(reference, 16);
        }
        else {
            value reference = gatherReference(nextChar, c0);
            if (is ParseError reference) {
                return reference;
            }
            
            code = parseInteger(reference);
        }
        
        if (exists code) {
            value char = code.character;
            if (!isChar(char)) {
                return ParseError("character reference for invalid character");
            }
            return code.character;
        }
        else {
            return ParseError("invalid character reference");
        }
    }
    else {
        return ParseError("EOF in character reference");
    }
}

String|ParseError replaceReference(String input)
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
                    if (is ParseError cr) {
                        return cr;
                    }
                    builder.appendCharacter(cr);
                    state = NState.simple;
                }
                else {
                    value reference = gatherReference(iterator.next, c);
                    if (is ParseError reference) {
                        return reference;
                    }
                    
                    value replacement = predefinedEntities[reference];
                    if (exists replacement) {
                        if (replacement.any((c) => c == '<')) {
                            return ParseError("illegale tag start in attribute value");
                        }
                        value rep = replaceReference(replacement);
                        if (is ParseError rep) {
                            return rep;
                        }
                        builder.append(rep);
                        state = NState.simple;
                    }
                    else {
                        return ParseError("undefined entity ``reference``");
                    }
                }
            }
            else {
                return ParseError("EOF in reference");
            }
        }
    }
}