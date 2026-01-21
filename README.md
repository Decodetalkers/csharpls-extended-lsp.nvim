# csharpls-extended-lsp.nvim

Extended `textDocument/definition` and `textDocument/typeDefinition` handler that handles assembly/decompilation
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
  local result, err = client.request_sync("csharp/metadata", params, 10000, 0) -- 0 is for current buffer
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

local result, err = client.request_sync("csharp/metadata", params, 10000, 0)
local source
if not err then
	source = result.result.source	
end
```

## Usage


To use this plugin all that needs to be done is for the nvim lsp handler for
`textDocument/definition` be overridden with one provided by this plugin.

If using `lspconfig` this can be done like this:

First configure omnisharp as per [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/CONFIG.md#omnisharp).

Then to that config add `handlers` with custom handlers from this plugin.

# For nvim 0.11

```lua
require'lspconfig'.csharp_ls.setup(config)
require("csharpls_extended").buf_read_cmd_bind()
```

# For fzf-lua

```lua
vim.keymap.set('n', 'gd', require('csharpls_extended_fzf').fzf,)
```

## Telescope (DEPRECATED - Telescope is not actively maintained)

```lua
require("telescope").load_extension("csharpls_definition")
```


### Thanks to [omnisharp-extended-lsp.nvim](https://github.com/Hoffs/omnisharp-extended-lsp.nvim) 
### Thanks to the help of [csharp-language-server](https://github.com/razzmatazz/csharp-language-server)
