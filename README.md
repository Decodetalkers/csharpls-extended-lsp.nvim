# csharpls-extended-lsp.nvim

Extended `textDocument/definition` handler that handles assembly/decompilation
loading for `$metadata$` documents.

## How it works

By providing an alternate handler for `textDocument/definition` the plugin listens
to all responses and if it receives URI with `$metadata$` it will call custom
omnisharp endpoint `o#/metadata` which returns full document source. This source
is then loaded as a scratch buffer with name set to `/$metadata$/..`. This allows
then allows jumping to the buffer based on name or from quickfix list, because it's
loaded.

csharpls use [ILSpy/ICSharpCode.Decompiler ](https://github.com/icsharpcode/ILSpy) to decompile code. So just get the uri and We can receive decompile sources from csahrpls

### api

The api is "csharp/metadata", in neovim ,you can request it like

```lua 
  local result, err = client.request_sync("csharp/metadata", params, 10000)
```

#### sender
You need to send a uri, it is like 

**csharp:/metadata/projects/trainning2/assemblies/System.Console/symbols/System.Console.cs**

In neovim, it will be result(s) from vim.lsp.handles["textDocument/definition"]

and the key of uri is the key, 

The key to send is like

```lua 
local params = {
	timeout = 5000,
	textDocument = {
		uri = uri,
	}
}
```

The key of textDocument is needed. And timeout is just for neovim. It is the same if is expressed by json.

### receiver

The object received is like 

```lua 
{
	projectName = "csharp-test",
	assemblyName = "System.Runtime",
	symbolName = "System.String",
	source = "using System.Buffers;\n ...."
}
```

And In neovim, You receive the "result" above, you can get the decompile source from 

```lua

local result, err = client.request_sync("csharp/metadata", params, 10000)
local source
if not err then
	source = result.result.source	
end
```

## Usage


### For Neovim >= 0.5

To use this plugin all that needs to be done is for the nvim lsp handler for
`textDocument/definition` be overriden with one provided by this plugin.

If using `lspconfig` this can be done like this:

First configure omnisharp as per [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/CONFIG.md#omnisharp).

Then to that config add `handlers` with custom handler from this plugin.

```lua
local pid = vim.fn.getpid()
-- On linux/darwin if using a release build, otherwise under scripts/OmniSharp(.Core)(.cmd)
-- on Windows
-- local omnisharp_bin = "/path/to/omnisharp/OmniSharp.exe"

local config = {
  handlers = {
    ["textDocument/definition"] = require('csharpls_extended').handler,
  },
  cmd = { csharpls },
  -- rest of your settings
}

require'lspconfig'.csharp_ls.setup(config)
```

### For Neovim 0.5.1

Due to the fact that in 0.5.1 request params are not available is handler
response a function to go to definitions has to be invoked manually. One option is to use
telescope method explained in the next section or to use `lsp_definitions()` function which
mimics standard definitions behavior.

```vimscript
nnoremap gd <cmd>lua require('csharp_ls_extended').lsp_definitions()<cr>
```

### Thanks to [omnisharp-extended-lsp.nvim](https://github.com/Hoffs/omnisharp-extended-lsp.nvim) 
### Thanks to the help of [csharp-language-server](https://github.com/razzmatazz/csharp-language-server)
