const TOKEN_KEY = "chat-finance-token";
const API_BASE = "/api/finance";

const DEFAULT_DATA = {
  settings: {
    monthlyIncome: 1000,
    month: "",
    cdiRate: 14.90,
    budget: {
      necessidades: 20,
      comida: 25,
      patrimonio: 30,
      objetivos: 15,
      lazer: 10
    }
  },

  investments: [],

  transactions: []
};

let data = structuredClone(DEFAULT_DATA);
let authToken = localStorage.getItem(TOKEN_KEY) || "";
let saveTimer = null;
let saveQueue = Promise.resolve();

const $ = id => document.getElementById(id);

const brl = value =>
  new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: "BRL"
  }).format(Number(value) || 0);

const percent = value =>
  `${Number(value || 0).toFixed(2).replace(".", ",")}%`;

function todayISO() {
  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

function showAuthGate(message = "") {
  const gate = $("authGate");
  if (!gate) return;
  gate.classList.remove("hidden");
  const error = $("authError");
  error.textContent = message;
  error.classList.toggle("hidden", !message);
  $("authToken").value = "";
  $("authToken").focus();
}

function hideAuthGate() {
  $("authGate").classList.add("hidden");
}

function readTokenFromHash() {
  if (!location.hash) return false;
  const params = new URLSearchParams(location.hash.slice(1));
  const token = (params.get("token") || "").trim();
  if (!token) return false;
  authToken = token;
  localStorage.setItem(TOKEN_KEY, token);
  history.replaceState(null, "", location.pathname + location.search);
  return true;
}

async function api(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
      ...(options.headers || {})
    }
  });

  if (response.status === 401) {
    showAuthGate("Token inválido. Cole o token do app Chat novamente.");
    throw new Error("Não autorizado");
  }

  if (!response.ok) {
    let detail = `Erro ${response.status}`;
    try {
      const body = await response.json();
      detail = body.detail || detail;
    } catch {
      // Mantém a mensagem genérica.
    }
    throw new Error(detail);
  }

  if (response.status === 204) return null;
  return response.json();
}

function mergeState(state) {
  return {
    ...structuredClone(DEFAULT_DATA),
    ...state,
    settings: {
      ...structuredClone(DEFAULT_DATA.settings),
      ...(state.settings || {}),
      budget: {
        ...structuredClone(DEFAULT_DATA.settings.budget),
        ...(state.settings?.budget || {})
      }
    },
    investments: state.investments || [],
    transactions: state.transactions || []
  };
}

async function loadState() {
  const state = await api("/state");
  data = mergeState(state);
  render();
}

function scheduleSave() {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    saveTimer = null;
    saveQueue = saveQueue.then(saveState).catch(error => {
      console.error("Falha ao salvar:", error);
    });
  }, 250);
}

async function saveState() {
  await api("/state", {
    method: "PUT",
    body: JSON.stringify({
      settings: data.settings,
      investments: data.investments
    })
  });
}

function calculateMonthlyCdi() {
  const annual = Number(data.settings.cdiRate) || 0;

  /*
   * Aproximação da taxa mensal equivalente:
   *
   * (1 + taxa anual)^(1/12) - 1
   */
  return Math.pow(1 + annual / 100, 1 / 12) - 1;
}

function calculateInvestmentRate(investment) {
  if (investment.type === "monthly") {
    return Number(investment.rate) || 0;
  }

  const cdiMonthly = calculateMonthlyCdi();

  return cdiMonthly * (Number(investment.cdiPercent) || 0) / 100 * 100;
}

function calculateInvestmentReturn(investment) {
  const amount = Number(investment.amount) || 0;

  const monthlyRate = calculateInvestmentRate(investment);

  return amount * monthlyRate / 100;
}

function renderSummary() {
  const totalInvestido = data.investments.reduce(
    (sum, investment) => sum + Number(investment.amount || 0),
    0
  );

  const totalRendimento = data.investments.reduce(
    (sum, investment) => sum + calculateInvestmentReturn(investment),
    0
  );

  const entradas = data.transactions
    .filter(item => item.type === "entrada")
    .reduce((sum, item) => sum + Number(item.value || 0), 0);

  const saidas = data.transactions
    .filter(item => item.type === "saida")
    .reduce((sum, item) => sum + Number(item.value || 0), 0);

  $("totalInvestido").textContent = brl(totalInvestido);
  $("totalRendimento").textContent = brl(totalRendimento);

  /*
   * Patrimônio estimado = capital investido + rendimento mensal estimado.
   */
  $("patrimonio").textContent = brl(
    totalInvestido + totalRendimento
  );

  $("entradas").textContent = brl(entradas);
  $("saidas").textContent = brl(saidas);

  const goal = 7500;

  $("goalBar").style.width =
    Math.min(100, totalInvestido / goal * 100) + "%";
}

function renderIncome() {
  $("monthlyIncome").value = data.settings.monthlyIncome;

  if (data.settings.month) {
    $("monthReference").value = data.settings.month;
  }

  $("cdiRate").value = data.settings.cdiRate;

  const monthlyCdi = calculateMonthlyCdi() * 100;

  $("monthlyCdi").textContent = percent(monthlyCdi);

  document
    .querySelectorAll(".budget-percent")
    .forEach(input => {
      input.value =
        data.settings.budget[input.dataset.category] || 0;
    });

  renderBudget();
}

function renderBudget() {
  const income = Number(data.settings.monthlyIncome) || 0;

  const categories = {
    necessidades: "budgetNecessidades",
    comida: "budgetComida",
    patrimonio: "budgetPatrimonio",
    objetivos: "budgetObjetivos",
    lazer: "budgetLazer"
  };

  let totalPercent = 0;

  Object.entries(categories).forEach(([category, elementId]) => {
    const percentage =
      Number(data.settings.budget[category]) || 0;

    totalPercent += percentage;

    const value = income * percentage / 100;

    $(elementId).textContent = brl(value);
  });

  $("percentageTotal").textContent =
    `${totalPercent}%`;

  const warning = $("percentageWarning");

  if (Math.abs(totalPercent - 100) > 0.01) {
    warning.classList.remove("hidden");
  } else {
    warning.classList.add("hidden");
  }
}

function renderInvestments() {
  const container = $("investmentList");

  if (!data.investments.length) {
    container.innerHTML = `
      <div class="empty">
        Nenhum investimento cadastrado.
      </div>
    `;

    return;
  }

  container.innerHTML = data.investments.map((investment, index) => {
    const rate = calculateInvestmentRate(investment);
    const monthlyReturn = calculateInvestmentReturn(investment);

    let description;

    if (investment.type === "monthly") {
      description = `${percent(rate)} ao mês`;
    } else {
      description =
        `${investment.cdiPercent}% do CDI · ${percent(rate)} a.m. estimado`;
    }

    return `
      <div class="investment">

        <div class="investment-top">
          <div>
            <div class="investment-name">
              ${escapeHTML(investment.name)}
            </div>

            <div class="investment-meta">
              ${description}
            </div>
          </div>

          <strong>
            ${brl(investment.amount)}
          </strong>
        </div>

        <div class="investment-return">
          <span class="small">
            Rendimento mensal estimado
          </span>

          <strong class="positive">
            +${brl(monthlyReturn)}
          </strong>
        </div>

        <button
          class="danger"
          style="margin-top:10px;padding:6px 9px;font-size:11px"
          onclick="removeInvestment(${index})"
        >
          excluir
        </button>

      </div>
    `;
  }).join("");
}

function renderTransactions() {
  const container = $("transactionList");

  const transactions = [...data.transactions]
    .sort((a, b) => b.date.localeCompare(a.date));

  if (!transactions.length) {
    container.className = "empty";
    container.innerHTML = "Nenhum lançamento ainda.";
    return;
  }

  container.className = "";

  container.innerHTML = transactions.map(transaction => {
    const positive =
      transaction.type === "entrada" ||
      transaction.type === "investimento";

    const signal =
      transaction.type === "saida" ? "−" : "+";

    const date = new Date(
      transaction.date + "T12:00:00"
    ).toLocaleDateString("pt-BR");

    return `
      <div class="row">

        <div>
          <strong>
            ${escapeHTML(
              transaction.note || transaction.category
            )}
          </strong>

          <div class="small">
            ${escapeHTML(transaction.category)} · ${date}
          </div>
        </div>

        <div style="text-align:right">

          <strong class="amount ${positive ? "pos" : "neg"}">
            ${signal}${brl(transaction.value)}
          </strong>

          <br>

          <button
            class="danger"
            style="padding:4px 7px;font-size:11px"
            onclick="removeTransaction('${escapeHTML(transaction.id)}')"
          >
            excluir
          </button>

        </div>

      </div>
    `;
  }).join("");
}

function render() {
  renderSummary();
  renderIncome();
  renderInvestments();
  renderTransactions();
}

function escapeHTML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

/* =========================
   RENDA
========================= */

$("monthlyIncome").addEventListener("input", event => {
  data.settings.monthlyIncome =
    Number(event.target.value) || 0;

  scheduleSave();
  renderBudget();
});

$("monthReference").addEventListener("change", event => {
  data.settings.month = event.target.value;

  scheduleSave();
});

$("cdiRate").addEventListener("input", event => {
  data.settings.cdiRate =
    Number(event.target.value) || 0;

  scheduleSave();

  $("monthlyCdi").textContent =
    percent(calculateMonthlyCdi() * 100);

  renderInvestments();
  renderSummary();
});

/* =========================
   DIVISÃO
========================= */

document
  .querySelectorAll(".budget-percent")
  .forEach(input => {

    input.addEventListener("input", event => {

      const category = event.target.dataset.category;

      data.settings.budget[category] =
        Number(event.target.value) || 0;

      scheduleSave();

      renderBudget();
    });
  });

/* =========================
   TIPO DE INVESTIMENTO
========================= */

$("investmentType").addEventListener("change", event => {

  const isCdi = event.target.value === "cdi";

  $("monthlyRateField")
    .classList.toggle("hidden", isCdi);

  $("cdiPercentField")
    .classList.toggle("hidden", !isCdi);
});

/* =========================
   NOVO INVESTIMENTO
========================= */

$("investmentForm").addEventListener("submit", event => {

  event.preventDefault();

  const name =
    $("investmentName").value.trim();

  const amount =
    Number($("investmentAmount").value);

  const type =
    $("investmentType").value;

  if (!name || amount <= 0) {
    return;
  }

  const rate =
    type === "monthly"
      ? Number($("investmentRate").value) || 0
      : 0;

  const cdiPercent =
    type === "cdi"
      ? Number($("investmentCdiPercent").value) || 0
      : 0;

  /*
   * Procura um investimento existente com:
   * - mesmo nome
   * - mesmo tipo de rendimento
   * - mesma taxa
   *
   * Assim, novos aportes são somados ao investimento
   * em vez de criar vários registros separados.
   */
  const existing = data.investments.find(investment =>
    investment.name.toLowerCase() === name.toLowerCase() &&
    investment.type === type &&
    (
      type === "monthly"
        ? Number(investment.rate) === rate
        : Number(investment.cdiPercent) === cdiPercent
    )
  );

  if (existing) {

    existing.amount =
      Number(existing.amount) + amount;

  } else {

    data.investments.push({
      id: crypto.randomUUID(),
      name,
      amount,
      type,
      rate,
      cdiPercent
    });

  }

  scheduleSave();

  event.target.reset();

  $("investmentType").value = "monthly";

  $("monthlyRateField")
    .classList.remove("hidden");

  $("cdiPercentField")
    .classList.add("hidden");

  render();
});
/* =========================
   LANÇAMENTOS
========================= */

$("transactionDate").value =
  todayISO();

$("transactionForm").addEventListener("submit", async event => {

  event.preventDefault();

  const value =
    Number($("transactionValue").value);

  if (value <= 0) {
    return;
  }

  const button = event.target.querySelector("button[type=submit]");
  button.disabled = true;

  try {

    const created = await api("/transactions", {
      method: "POST",
      body: JSON.stringify({
        type: $("transactionType").value,
        value,
        category: $("transactionCategory").value,
        date: $("transactionDate").value,
        note: $("transactionNote").value.trim()
      })
    });

    data.transactions.push(created);

    event.target.reset();

    $("transactionDate").value =
      todayISO();

    render();

  } catch (error) {

    alert(`Não foi possível registrar o lançamento: ${error.message}`);

  } finally {

    button.disabled = false;

  }
});

async function removeTransaction(id) {

  if (!confirm("Excluir este lançamento?")) {
    return;
  }

  try {

    await api(`/transactions/${encodeURIComponent(id)}`, {
      method: "DELETE"
    });

    data.transactions =
      data.transactions.filter(item => item.id !== id);

    render();

  } catch (error) {

    alert(`Não foi possível excluir o lançamento: ${error.message}`);

  }
}

/* =========================
   LIMPAR TUDO
========================= */

$("clearData").addEventListener("click", async () => {

  if (!confirm(
    "Isso apagará renda, investimentos e histórico. Continuar?"
  )) {
    return;
  }

  try {

    await api("/reset", { method: "POST" });
    await loadState();

    $("transactionDate").value =
      todayISO();

  } catch (error) {

    alert(`Não foi possível apagar os dados: ${error.message}`);

  }
});

document.addEventListener("visibilitychange", () => {
  if (document.hidden || !authToken) return;
  if (saveTimer) {
    clearTimeout(saveTimer);
    saveTimer = null;
    saveQueue = saveQueue.then(saveState).catch(error => {
      console.error("Falha ao salvar:", error);
    });
  }
  saveQueue = saveQueue.then(loadState).catch(error => {
    console.error("Falha ao atualizar:", error);
  });
});

/* =========================
   CONEXÃO COM O CHAT
========================= */

$("authForm").addEventListener("submit", async event => {

  event.preventDefault();

  const token = $("authToken").value.trim();

  if (!token) {
    return;
  }

  authToken = token;
  localStorage.setItem(TOKEN_KEY, token);

  try {

    await loadState();
    hideAuthGate();

  } catch (error) {

    if (error.message !== "Não autorizado") {
      showAuthGate(`Não foi possível conectar: ${error.message}`);
    }

  }
});

/* =========================
   SERVICE WORKER
========================= */

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("./sw.js")
    .catch(error => {
      console.error(
        "Falha ao registrar Service Worker:",
        error
      );
    });
}

/* =========================
   INICIALIZAÇÃO
========================= */

async function init() {

  readTokenFromHash();

  if (!authToken) {
    render();
    showAuthGate("Cole o token do app Chat para começar.");
    return;
  }

  try {

    await loadState();
    hideAuthGate();

  } catch (error) {

    console.error(error);
    render();

    if (error.message !== "Não autorizado") {
      showAuthGate(`Não foi possível conectar: ${error.message}`);
    }

  }
}

void init();