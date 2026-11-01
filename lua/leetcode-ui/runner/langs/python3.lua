--- *LeetCodeRunnerPython* Python3 local runner
---

-- |leetcode-ui-runner-lang| Local Python 3 harness (`runner/langs/python3`).
-- Wraps the user's `class Solution` with LeetCode-standard data structures,
-- a decoder for raw testcase lines, and a `print()` of the serialized return
-- value. SystemDesign problems drive the `classname` object through the method
-- list (see |runner/common|).
--
-- Run contract: argv = [python, main.py, lines_json, specs_json, mode]
--   lines_json  - array of raw testcase lines
--   specs_json  - normal: array of param type strings
--                 systemdesign: array of { name, types = {...} } per method
--   mode        - 'normal' | 'systemdesign'

local LeetCodeRunnerPython = {}

local config = require('leetcode-ui.config')

-- Helper data =======================================================================================================

LeetCodeRunnerPython.prelude = [=[
from typing import *
from collections import *
from math import *    # noqa
import json, sys

class TreeNode:
    def __init__(self, val=0, left=None, right=None):
        self.val = val
        self.left = left
        self.right = right

class ListNode:
    def __init__(self, val=0, next=None):
        self.val = val
        self.next = next

class Node:
    def __init__(self, val=0, children=None, neighbors=None, next=None, random=None):
        self.val = val
        self.children = children if children is not None else []
        self.neighbors = neighbors if neighbors is not None else []
        self.next = next
        self.random = random

def _tree(arr):
    if not arr:
        return None
    root = TreeNode(arr[0])
    queue, i = [root], 1
    while queue and i < len(arr):
        node = queue.pop(0)
        if i < len(arr) and arr[i] is not None:
            node.left = TreeNode(arr[i])
            queue.append(node.left)
        i += 1
        if i < len(arr) and arr[i] is not None:
            node.right = TreeNode(arr[i])
            queue.append(node.right)
        i += 1
    return root

def _tree_plain(node):
    out, queue = [], [node] if node else []
    while queue:
        cur = queue.pop(0)
        if cur is not None:
            out.append(cur.val)
            queue.append(cur.left)
            queue.append(cur.right)
        elif out:
            out.append(None)
    while out and out[-1] is None:
        out.pop()
    return out

def _list(arr):
    dummy = ListNode()
    cur = dummy
    for v in arr:
        cur.next = ListNode(v)
        cur = cur.next
    return dummy.next

def _list_plain(node):
    out, seen = [], set()
    while node is not None and id(node) not in seen:
        seen.add(id(node))
        out.append(node.val)
        node = node.next
    return out

def _walk_default(obj):
    if isinstance(obj, TreeNode):
        return _tree_plain(obj)
    if isinstance(obj, ListNode):
        return _list_plain(obj)
    if isinstance(obj, Node):
        return {'$node': obj.val}
    return str(obj)

def _lc_encode(value, kind=''):
    if value is None:
        return 'null'
    t = kind or ''
    if t == 'integer' or t == 'double':
        return str(value)
    if t == 'boolean':
        return 'true' if value else 'false'
    if t == 'string':
        return value
    if t == 'TreeNode':
        return json.dumps(_tree_plain(value), separators=(',', ':'))
    if t == 'ListNode':
        return json.dumps(_list_plain(value), separators=(',', ':'))
    return json.dumps(value, default=_walk_default, separators=(',', ':'))

def _lc_decode(kind, raw):
    data = json.loads(raw) if isinstance(raw, str) else raw
    if kind == 'TreeNode':
        return _tree(data)
    if kind == 'ListNode':
        return _list(data)
    return data
]=]

LeetCodeRunnerPython.normal_entry = [=[
def __lc_main__():
    lines = json.loads(sys.argv[1])
    types = json.loads(sys.argv[2])
    args = [_lc_decode(types[i], lines[i]) for i in range(min(len(types), len(lines)))]
    solution = Solution()
    result = solution.__lc_method__(*args)
    print(_lc_encode(result, '__lc_return__'))

if __name__ == '__main__':
    __lc_main__()
]=]

LeetCodeRunnerPython.system_entry = [=[
def __lc_main__():
    lines = json.loads(sys.argv[1])
    specs = json.loads(sys.argv[2])
    names, argss = json.loads(lines[0]), json.loads(lines[1])
    cls = globals()['__lc_class__']
    spec_by_name = {spec.get('name'): spec for spec in specs}
    obj, outs = None, []
    for i, name in enumerate(names):
        if name == '__lc_class__':
            obj = cls()
            outs.append('null')
            continue
        argtypes = (spec_by_name.get(name) or {}).get('types') or []
        args = [_lc_decode(argtypes[j], a) for j, a in enumerate(argss[i] or [])]
        result = getattr(obj, name)(*args)
        outs.append(_lc_encode(result))
    print('[' + ','.join(outs) + ']')

if __name__ == '__main__':
    __lc_main__()
]=]

-- Helper functionality =============================================================================================

LeetCodeRunnerPython.available = function()
  local binary = (config.config.binaries or {}).python3 or 'python3'
  if vim.fn.executable(binary) == 1 then return true, nil end
  return false, ('`%s` is not executable'):format(binary)
end

LeetCodeRunnerPython.build = function(code, kind, opt)
  local entry = kind == 'systemdesign' and LeetCodeRunnerPython.system_entry or LeetCodeRunnerPython.normal_entry
  local piece = entry:gsub('__lc_method__', opt.name or '')
  piece = piece:gsub('__lc_return__', opt.return_type or '')
  piece = piece:gsub('__lc_class__', opt.class_name or '')
  return LeetCodeRunnerPython.prelude .. '\n\n' .. code .. '\n\n' .. piece
end

LeetCodeRunnerPython.run = function(dir, _question, code, params, data_lines)
  local binary = (config.config.binaries or {}).python3 or 'python3'
  local main = vim.fs.joinpath(dir, 'main.py')

  if params.mode == 'systemdesign' then
    local specs = {}
    for _, method in ipairs(params.methods or {}) do
      local types = {}
      for _, arg in ipairs(method.params or {}) do
        table.insert(types, arg.type)
      end
      table.insert(specs, { name = method.name, types = types })
    end

    local source = LeetCodeRunnerPython.build(code, 'systemdesign', { class_name = params.class_name })
    vim.fn.writefile(vim.split(source, '\n'), main)

    return {
      binary,
      main,
      vim.json.encode(data_lines or {}),
      vim.json.encode(specs),
      'systemdesign',
    }
  end

  local types = {}
  for _, param in ipairs(params.params or {}) do
    table.insert(types, param.type)
  end
  local types_json = vim.json.encode(types)

  local source = LeetCodeRunnerPython.build(code, 'normal', { name = params.name, return_type = params.return_type })
  vim.fn.writefile(vim.split(source, '\n'), main)
  return { binary, main, vim.json.encode(data_lines or {}), types_json, 'normal' }
end

return LeetCodeRunnerPython
