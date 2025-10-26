KipuBankV2

KipuBankV2 es una bóveda multi-activo (multi-asset vault) que permite a los usuarios depositar y extraer Ether o tokens ERC-20, con límites definidos en USD.  
El contrato utiliza un oráculo de Chainlink para obtener el precio ETH/USD y mantener un control de riesgo sobre el valor total depositado.  
Solo el propietario (owner) puede realizar operaciones administrativas, garantizando la seguridad del sistema.

---

## Resumen de mejoras y motivaciones

### 1. Control de riesgo mediante límites en USD
- Motivación: Evitar que la bóveda acumule más valor del permitido y proteger la liquidez total.
- Implementación:
  - `i_bankCapUSD`: límite máximo total en USD de todos los depósitos combinados.
  - `i_maxExtractUSD`: límite máximo permitido por extracción individual.
  - Ambos son inmutables, definidos al desplegar el contrato.

### 2. Integración con Chainlink ETH/USD
- Motivación: Convertir depósitos en ETH a su valor en USD con un precio confiable.
- Implementación:  
  Se utiliza `AggregatorV3Interface` para leer precios del oráculo Chainlink.

### 3. Soporte multi-activo
- Motivación: Permitir depósitos tanto en Ether nativo como en tokens ERC-20.
- Implementación:  
  - `mapping(address => mapping(address => uint256)) s_accounts;`  
  - `address(0)` representa ETH, mientras que cualquier otra dirección corresponde a un token ERC-20.

### 4. Seguridad reforzada
- Motivación: Proteger fondos de usuarios y evitar comportamientos no deseados.
- Implementación:
  - Hereda `Ownable` (OpenZeppelin) para control de propiedad.
  - Usa modificadores y errores personalizados para validar límites, montos nulos o fallos de transferencia.
  - Bloquea envíos directos de ETH al contrato (`receive()` revertido).

### 5. Eficiencia de gas y claridad
- Motivación: Reducir costos y riesgos de errores.
- Implementación:
  - Uso de `unchecked` cuando las operaciones son seguras.
  - Actualizaciones de balances realizadas en memoria antes de escribir en almacenamiento.
  - Enums (`Operation`) para mayor legibilidad.

---

## Despliegue en Remix

### Requisitos previos
1. Accede a [Remix IDE](https://remix.ethereum.org)
2. Crea un nuevo archivo llamado `KipuBankV2.sol` y pega el contenido completo del contrato.
3. En la pestaña Solidity Compiler:
   - Selecciona la versión `0.8.30`
   - Compila el contrato
4. En la pestaña Deploy & Run Transactions:
   - Selecciona el entorno (por ejemplo: Injected Provider - MetaMask o Remix VM)
   - Completa los parámetros del constructor:
     - `_maxExtractUSD` → cantidad máxima por extracción, en 6 decimales (por ejemplo, 1000 USD → `1000000000`)
     - `_bankCapUSD` → límite total del banco, en 6 decimales (por ejemplo, 100000 USD → `100000000000`)
     - `_priceFeedAddress` → dirección del oráculo Chainlink ETH/USD (por ejemplo, en Sepolia: `0x694AA1769357215DE4FAC081bf1f309aDC325306`)
   - Haz clic en Deploy

Ejemplo de parámetros:

_maxExtractUSD = 1000000000
_bankCapUSD = 100000000000
_priceFeedAddress = 0x694AA1769357215DE4FAC081bf1f309aDC325306 // dirección del oráculo Chainlink ETH/USD

---

## Interacción en Remix

### Depositar ETH
1. Selecciona la función `depositETH`
2. Ingresa el valor de ETH a enviar en el campo `Value` (por ejemplo, `0.5 ether`)
3. Haz clic en Transact

El contrato calculará automáticamente el valor USD del depósito según Chainlink.

---

### Depositar tokens ERC-20
1. Obtén la dirección del token ERC-20 (por ejemplo, USDC o un token propio).
2. Primero, aprueba el gasto del contrato desde el token:
   - En el contrato del token, ejecuta:
     ```
     approve(<DIRECCION_DE_KIPUBANKV2>, <CANTIDAD>)
     ```
3. Luego, en `KipuBankV2`, ejecuta:

depositERC20(_token, _amount)

Ejemplo:

_token = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 // Ejemplo no verificado
_amount = 1000000 // equivalente a 1 USDC (6 decimales)

---

### Extraer fondos
1. Usa la función:

extractFromAccount(_token, _quantity)

Ejemplo:

_token = 0x0000000000000000000000000000000000000000 // ETH
_quantity = 500000000000000000 // 0.5 ETH

2. La extracción se validará contra:
- Límite máximo en USD (`i_maxExtractUSD`)
- Balance del usuario
- Límite total del banco

---

### Consultar balance
Usa:

getBalance(_token)

Ejemplo:

_token = 0x0000000000000000000000000000000000000000 // ETH

El resultado mostrará el saldo del usuario en decimales nativos del token.

---

## Decisiones de diseño y trade-offs

### 1. Oráculo ETH/USD único
- Se utiliza solo el par ETH/USD de Chainlink.
- Los ERC-20 se consideran equivalentes a USD (1:1) para simplificar.
- Trade-off: Menor precisión para tokens que no estén realmente anclados al dólar.

### 2. Límites inmutables
- Los límites de extracción y depósito total son `immutable`, definidos al desplegar.
- Ventaja: Transparencia y seguridad.
- Desventaja: No se pueden ajustar dinámicamente sin redeploy.

### 3. Balance en decimales nativos
- Los balances se guardan tal cual en las decimales del token.
- Ventaja: Evita redondeos y simplifica interacción.
- Desventaja: Requiere atención al mostrar valores al usuario.

### 4. Aritmética nativa sin librerías externas
- Se prioriza eficiencia y compatibilidad.
- Desventaja: No se manejan decimales arbitrarios ni precisión extendida.

---

## Stack y dependencias

- Solidity: 0.8.30  
- OpenZeppelin Contracts: `Ownable`, `IERC20`  
- Chainlink: `AggregatorV3Interface` (para precios ETH/USD)  
- No requiere `npm`, `hardhat` ni instalación adicional en Remix.  
- Se puede desplegar directamente con MetaMask.

---

## Licencia

BSD 3-Clause License

© 2025 ErickFCS — Todos los derechos reservados.