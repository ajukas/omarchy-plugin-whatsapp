# ajukas.whatsapp

Widget da barra do Omarchy para o WhatsApp Web.

- Clique esquerdo: abre o WhatsApp Web (via `omarchy-launch-webapp`) ou mostra/esconde o popup.
- O WhatsApp abre como janela flutuante de 1300x850 no canto superior direito, no
  workspace especial `special:whatsapp`. Ao focar outra janela ele some, mas continua
  rodando. Toda vez que abre, volta para o tamanho e a posição padrão.
- Se a janela for arrastada para fora do popup, ela volta para ele assim que perder o foco.
- Clicar no papel de parede ou numa área vazia também esconde o popup: o widget põe uma
  camada invisível embaixo das janelas enquanto ele está aberto.

A lógica de mostrar/esconder fica em `whatsapp-popup.sh`; o tamanho e a margem são
configurados no topo dele.
- Clique direito: fecha a janela.
- Clique do meio: limpa o contador.
- Cada notificação do WhatsApp aumenta o contador no ícone; ele zera ao focar a janela.

O contador observa `~/.local/state/omarchy/notifications/`, onde o shell grava as
notificações recebidas. Para funcionar, as notificações precisam estar ativadas no
WhatsApp Web.

## Instalação

```sh
ln -s ~/project/plugins/ajukas.whatsapp ~/.config/omarchy/plugins/ajukas.whatsapp
omarchy-shell shell rescanPlugins
omarchy plugin enable ajukas.whatsapp
```

Como o plugin é um link simbólico, edições aqui não recarregam sozinhas; rode
`omarchy restart shell` depois de alterar o código.

## Regra do Hyprland

O popup depende desta regra em `~/.config/hypr/hyprland.lua`:

```lua
o.window(".*-web\\.whatsapp\\.com__.*", {
  workspace = "special:whatsapp",
  float = true,
  size = { 1300, 850 },
  move = { "(monitor_w-window_w-12)", "38" },
})
```
