import ceylon.collection {
    Stack,
    ArrayList,
    HashMap,
    MutableMap
}

shared interface NamespaceContext
{
    shared formal String? namespaceName(String prefix);
    shared formal {<String->String>*} bindings();
}

class NamespaceContextImpl
satisfies NamespaceContext
{
    MutableMap<String, Stack<String>> scopes;
    
    shared new()
    {
        scopes = HashMap<String, Stack<String>>();
    }
    
    shared void push(String -> String prefixBinding)
    {
        Stack<String> stack;
        if (exists scope = scopes[prefixBinding.key]) {
            stack = scope;
        }
        else {
            stack = ArrayList<String>();
            scopes.put(prefixBinding.key, stack);
        }
        stack.push(prefixBinding.item);
    }
    
    shared String? pop(String key)
    {
        return scopes[key]?.pop();
    }
    
    shared String? top(String key)
    {
        return scopes[key]?.top;
    }
    
    shared actual String? namespaceName(String prefix) => top(prefix);
    
    shared actual {<String->String>*} bindings() => { for (e in scopes) let (nsName = e.item.top) if (exists nsName) then e.key -> nsName else null}.coalesced;
}

class ChainingIterator<Element>({Iterator<Element>*} iterators)
    satisfies Iterator<Element>
{
    value iterIter = iterators.iterator();
    variable Iterator<Element>|Finished current = iterIter.next();
    shared actual Element|Finished next()
    {
        if (!is Finished cr = current) {
            if (!is Finished it = cr.next()) {
                return it;
            }
            while (!is Finished ii = iterIter.next()) {
                if (!is Finished it = ii.next()) {
                    current = ii;
                    return it;
                }
            }
            current = finished;
            return finished;
        }
        else {
            return finished;
        }
    }
}
