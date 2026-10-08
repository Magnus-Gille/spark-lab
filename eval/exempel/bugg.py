def unika(l):
    r = []
    for i in range(len(l)):
        if l[i] not in r:
            r.append(l[i])
    return r
