# VendaFácil

Protótipo acadêmico de um ERP para pequenos comércios. A interface web em Flutter usa Supabase Auth e PostgreSQL.

## Usar o sistema

1. Cadastre e confirme uma conta por e-mail. Entre para cadastrar uma loja.
2. Em **Produtos**, cadastre mercadorias com código, preço, estoque inicial e estoque mínimo.
3. Em **Nova venda**, adicione os produtos ao carrinho, ajuste as quantidades e confirme. Dinheiro, Pix e cartões são registrados para demonstração.
4. Em **Histórico**, abra uma operação para consultar seus itens. A administração pode cancelar a venda e devolver os itens ao estoque.
5. Em **Relatórios**, consulte o faturamento diário ou mensal no horário de Brasília. Vendas canceladas são excluídas do faturamento.
6. Para compartilhar acesso, o operador primeiro cria e confirma sua conta. Na loja, um administrador abre **Opções da loja → Adicionar operador** e informa o e-mail. O operador atualiza **Minhas lojas** para visualizar a loja.

A administração gerencia produtos, libera operadores e cancela vendas. Operadores consultam produtos, alertas, histórico e relatórios e registram vendas. O banco limita cada conta às suas lojas e valida os privilégios de escrita. A confirmação de uma venda verifica preços e quantidades no servidor e atualiza o estoque dentro da mesma transação.

## Desenvolvimento

Com Flutter 3.50.1 e um projeto Supabase configurado, execute:

```bash
flutter pub get
flutter analyze
flutter run -d chrome --web-port=8080 --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_KEY=sb_publishable_EXEMPLO
```

Para aplicar as migrações a um projeto de desenvolvimento, use a CLI Supabase v2 e o URL do pooler em modo sessão, com porta 5432:

```bash
supabase db push --db-url "$SUPABASE_DB_URL"
```

As configurações do Supabase Auth pertencem ao projeto Supabase. Configure o **Site URL** com o endereço do site publicado e mantenha o cadastro por e-mail com confirmação habilitado. Para aceitar cadastros de usuários externos à organização Supabase, conecte um provedor SMTP no Supabase Auth.

## Publicar

1. No repositório público no GitHub, selecione **Settings → Pages → GitHub Actions** como fonte.
2. Em **Settings → Secrets and variables → Actions**, defina as variáveis `SUPABASE_URL` e `SUPABASE_KEY` (chave pública `sb_publishable_…` ou `anon`).
3. Defina o secret `SUPABASE_DB_URL` com a string do pooler em modo sessão, incluindo a senha do banco codificada para URL e `sslmode=require`. A string de conexão, a senha e as chaves privadas devem permanecer fora do código.
4. Ao receber um push em `main`, o workflow analisa e compila o Flutter, aplica as migrações pendentes e publica o artefato no Pages. A opção **Run workflow** permite repetir a publicação.
