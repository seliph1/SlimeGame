const DIFF_NIL = '__NIL'; // Sentinel to encode `nil`-ing in diffs

function nonempty(obj) {
    for (const _ in obj) return true;
    return false;
}

function serializable(v) {
    return typeof v !== 'function' && typeof v !== 'symbol';
}

// `proxy` per `node` that stores metadata.
//
//    `.name`: name
//    `.children`: `child.name` -> `child` (leaf or node) for all children
//    `.parent`: parent node, `null` if root
//
//    `.dirty`: `child.name` -> `true` if that key is dirty
//    `.dirtyRec`: whether all keys are dirty recursively
//    `.autoSync`: `true` for auto-sync just here, `'rec'` for recursive
//
//    `.caches`: diff-related caches for this subtree till next flush
//
//    `.relevanceDescs`: `child.name` -> `true` for keys that have a descendant with relevance
//
//  The following are non-null only if this exact node has relevance
//
//    `.relevance`: the relevance function if given, `true` if some descendant has one, else `null`
//    `.lastRelevancies`: `client` -> `k` -> non-null map for relevancies before flush
//    `.nextRelevancies`: `client` -> `k` -> non-null map for relevancies till next flush
//
const proxies = new WeakMap();

const Methods = {
    // `'name1:name2:...:nameN'` on path to this node
    __path() {
        const proxy = proxies.get(this);
        return (proxy.parent ? (Methods.__path.call(proxy.parent) + ':') : '') + String(proxy.name);
    },

    // This node as a plain object
    __table() {
        return proxies.get(this).children;
    },

    // Mark key `k` for sync. If `k` is `null`/`undefined` and `rec` is `true`, marks everything recursively.
    __sync(k, rec) {
        let proxy = proxies.get(this);

        // Abort if any ancestor has `.dirtyRec` since that means we're all dirty anyways
        {
            let p = proxy;
            while (true) {
                if (p.dirtyRec) return;
                const parent = p.parent;
                if (!parent) break;
                p = proxies.get(parent);
            }
        }

        while (true) {
            const dirty = proxy.dirty;
            let somePrevDirty;
            if (k == null) {
                if (rec) {
                    proxy.dirtyRec = true;
                }
                somePrevDirty = nonempty(dirty);
            } else {
                if (dirty[k]) return;
                somePrevDirty = nonempty(dirty);
                dirty[k] = true;
            }
            if (somePrevDirty) return;

            const parent = proxy.parent;
            if (!parent) return;
            k = proxy.name;
            proxy = proxies.get(parent);
        }
    },

    // Get the diff of this node since the last flush.
    //   `client`: the client to get the diff w.r.t
    //   `exact`: whether to get an 'exact' diff of everything
    __diff(client, exact, alreadyExact, caches) {
        const proxy = proxies.get(this);
        exact = exact || proxy.dirtyRec;

        // Initialize caches for this subtree if not already present
        if (!caches) {
            caches = proxy.caches;
            if (!caches) {
                caches = { diff: new Map(), diffRec: new Map() };
                proxy.caches = caches;
            }
        }

        // Check in caches first
        let ret;
        if (exact) {
            ret = caches.diffRec.get(this);
        } else {
            ret = caches.diff.get(this);
        }
        if (!ret) {
            ret = {};

            // Don't cache if we or a descendant has relevance (results change per client)
            const relevance = proxy.relevance;
            const relevanceDescs = proxy.relevanceDescs;
            const skipCache = relevance || (relevanceDescs && nonempty(relevanceDescs));
            if (!alreadyExact && exact) {
                ret.__exact = true;
                alreadyExact = true;
                if (!skipCache) {
                    caches.diffRec.set(this, ret);
                }
            } else if (!exact && !skipCache) {
                caches.diff.set(this, ret);
            }

            const children = proxy.children;
            const dirty = proxy.dirty;

            if (relevance) {
                // Has a relevance function -- only go through children in relevancy
                const lastRelevancy = proxy.lastRelevancies.get(client);
                const relevancy = relevance(this, client);
                proxy.nextRelevancies.set(client, relevancy);
                for (const k in relevancy) {
                    const exactHere = exact || (!lastRelevancy || !lastRelevancy[k]);
                    if (exactHere || dirty[k]) {
                        const v = children[k];
                        if (proxies.has(v)) {
                            ret[k] = Methods.__diff.call(v, client, exactHere, alreadyExact, caches);
                        } else if (v === undefined) {
                            if (!exact) {
                                ret[k] = DIFF_NIL;
                            }
                        } else if (serializable(v)) {
                            ret[k] = v;
                        }
                    }

                    // Filter any variable with (_) prefix
                    if (typeof k === 'string' && /^_[^_]/.test(k)) delete ret[k];
                }
                if (!exact) {
                    if (lastRelevancy) {
                        for (const k in lastRelevancy) {
                            if (!relevancy[k]) {
                                ret[k] = DIFF_NIL;
                            }
                            if (typeof k === 'string' && /^_[^_]/.test(k)) delete ret[k];
                        }
                    }
                }
            } else {
                // No relevance function -- if `exact` go through all children, else just `dirty` ones
                const source = exact ? children : dirty;
                for (const k in source) {
                    const v = children[k];
                    if (proxies.has(v)) {
                        ret[k] = Methods.__diff.call(v, client, exact, alreadyExact, caches);
                    } else if (v === undefined) {
                        ret[k] = DIFF_NIL;
                    } else if (serializable(v)) {
                        ret[k] = v;
                    }
                    // Filter any variable with (_) prefix
                    if (typeof k === 'string' && /^_[^_]/.test(k)) delete ret[k];
                }
            }
        }
        return (exact || nonempty(ret)) ? ret : null;
    },

    // Unmark everything recursively. If `getDiff`, returns what the diff was before flushing.
    __flush(getDiff, client) {
        const diff = getDiff ? Methods.__diff.call(this, client) : null;
        const proxy = proxies.get(this);
        const children = proxy.children;
        const dirty = proxy.dirty;
        const relevanceDescs = proxy.relevanceDescs;

        if (relevanceDescs) {
            for (const k in relevanceDescs) {
                const v = children[k];
                if (v !== undefined && proxies.has(v)) {
                    Methods.__flush.call(v);
                } else {
                    delete relevanceDescs[k];
                }
                delete dirty[k];
            }
        }
        for (const k in dirty) {
            const v = children[k];
            if (proxies.has(v)) {
                Methods.__flush.call(v);
            }
            delete dirty[k];
        }
        proxy.dirtyRec = false;

        // Reset caches
        proxy.caches = null;

        // Transfer relevancy info to `.lastRelevancies`
        const nextRelevancies = proxy.nextRelevancies;
        if (nextRelevancies) {
            const lastRelevancies = proxy.lastRelevancies;
            for (const [client, rel] of nextRelevancies) {
                lastRelevancies.set(client, rel);
            }
            for (const [client] of lastRelevancies) {
                if (!nextRelevancies.has(client)) {
                    lastRelevancies.delete(client);
                }
            }
            nextRelevancies.clear();
        }

        return diff;
    },

    // Mark node for 'auto-sync'. If `rec` is true, all descendant nodes are marked too.
    __autoSync(rec) {
        const proxy = proxies.get(this);
        const node = this;

        if (!proxy.autoSync) {
            const children = proxy.children;
            const handler = proxy._proxyHandler;
            const oldSet = handler.set.bind(handler);

            handler.set = function (target, k, v, receiver) {
                if (children[k] !== v) {
                    oldSet(target, k, v, receiver);
                    Methods.__sync.call(node, k);
                }
                return true;
            };

            proxy.autoSync = true;
        }

        if (proxy.autoSync !== 'rec' && rec) {
            for (const k in proxy.children) {
                const v = proxy.children[k];
                if (proxies.has(v)) {
                    Methods.__autoSync.call(v, true);
                }
            }
            proxy.autoSync = 'rec';
        }
    },

    // Set the relevance function for a node.
    __relevance(relevance) {
        const proxy = proxies.get(this);

        if (proxy.relevance) {
            proxy.relevance = relevance;
            return;
        }

        // Tell ancestors
        let curr = proxy;
        while (curr.parent) {
            const parent = proxies.get(curr.parent);
            if (!parent.relevanceDescs) {
                parent.relevanceDescs = {};
            }
            parent.relevanceDescs[curr.name] = true;
            curr = parent;
        }

        // Set up relevance data for this node
        proxy.relevance = relevance;
        proxy.lastRelevancies = new Map();
        proxy.nextRelevancies = new Map();
    },
};

// Make a node out of `t` with given `name`, makes a root node if `parent` is `null`
function adopt(parent, name, t) {
    let node, proxy;

    if (proxies.has(t)) {
        // Was already a node -- reuse
        node = t;
        proxy = proxies.get(t);
        if (!proxy.parent) {
            throw new Error('tried to adopt a root node');
        }
    } else {
        // New node
        proxy = {};

        const children = {};
        proxy.children = children;

        // Initialize dirtiness
        proxy.dirty = {};
        proxy.dirtyRec = false;
        proxy.autoSync = false;
        proxy.relevance = null;
        proxy.lastRelevancies = null;
        proxy.nextRelevancies = null;
        proxy.relevanceDescs = null;
        proxy.caches = null;

        const handler = {
            get(target, k) {
                if (k in Methods) {
                    return Methods[k];
                }
                return children[k];
            },
            set(target, k, v) {
                const vProxy = proxies.has(v) ? proxies.get(v) : null;
                if (typeof v !== 'object' && v !== null && !vProxy) {
                    // Leaf -- just set
                    children[k] = v;
                } else if (children[k] !== v) {
                    const child = children[k];
                    const childProxy = proxies.has(child) ? proxies.get(child) : null;
                    if (!childProxy) {
                        adopt(node, k, v != null ? v : {});
                    } else {
                        const childChildren = childProxy.children;
                        const vChildren = vProxy ? vProxy.children : v;
                        let nSame = 0, nNew = 0, nRemove = 0;
                        for (const kp in vChildren) {
                            if (childChildren[kp] !== undefined) {
                                nSame++;
                            } else {
                                nNew++;
                            }
                        }
                        for (const kp in childChildren) {
                            if (vChildren[kp] === undefined) {
                                nRemove++;
                            }
                        }
                        if (nSame < nNew + 0.5 * nRemove) {
                            adopt(node, k, v != null ? v : {});
                        } else {
                            for (const kp in vChildren) {
                                child[kp] = vChildren[kp];
                            }
                            for (const kp in childChildren) {
                                if (vChildren[kp] === undefined) {
                                    child[kp] = undefined;
                                }
                            }
                        }
                    }
                }
                return true;
            },
            deleteProperty(target, k) {
                delete children[k];
                return true;
            },
            has(target, k) {
                return k in children || k in Methods;
            },
            ownKeys() {
                return Object.keys(children);
            },
            getOwnPropertyDescriptor(target, k) {
                if (k in children) {
                    return { configurable: true, enumerable: true, value: children[k] };
                }
                return undefined;
            },
        };

        proxy._proxyHandler = handler;
        node = new Proxy({}, handler);
        proxies.set(node, proxy);

        // Copy initial data
        for (const k in t) {
            if (Object.prototype.hasOwnProperty.call(t, k)) {
                handler.set(null, k, t[k]);
            }
        }
        // Handle array-like tables (numeric indices)
        if (Array.isArray(t)) {
            for (let i = 0; i < t.length; i++) {
                handler.set(null, i, t[i]);
            }
        }
    }

    // Set name and join parent link
    proxy.name = name;
    if (parent) {
        proxy.parent = parent;
        const parentProxy = proxies.get(parent);
        parentProxy.children[name] = node;

        if (parentProxy.autoSync === 'rec') {
            Methods.__sync.call(node, null, true);
            Methods.__autoSync.call(node, true);
        }
    }

    return node;
}

// Apply a diff from `:__diff` or `:__flush` to a target `t`
function apply(t, diff) {
    if (diff == null) return t;
    if (diff.__exact) {
        delete diff.__exact;
        return diff;
    }
    t = (typeof t === 'object' && t !== null) ? t : {};
    for (const k in diff) {
        const v = diff[k];
        if (typeof v === 'object' && v !== null) {
            t[k] = apply(t[k], v);
        } else if (v === DIFF_NIL) {
            delete t[k];
        } else {
            t[k] = v;
        }
    }
    return t;
}

module.exports = {
    new: function (t, name) {
        return adopt(null, name || 'root', t || {});
    },

    apply,

    isState: function (t) {
        return proxies.has(t);
    },
    getProxy: function (t) {
        return proxies.get(t);
    },

    DIFF_NIL,
};
