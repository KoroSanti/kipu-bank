// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title KipuBank
 * @author Rodriguez Santiago
 * @notice Banco descentralizado que permite depositar y retirar ETH con seguridad
 */
contract KipuBank {
    
    // ============================================
    // VARIABLES INMUTABLES Y CONSTANTES
    // ============================================
    
    /**
     * @notice Límite máximo que un usuario puede retirar en una sola transacción
     * @dev Variable inmutable: se establece en el constructor y nunca cambia
     * Esto ahorra gas porque no necesita ser leída desde storage
     * Ejemplo: Si se establece en 1 ether, nadie puede retirar más de 1 ETH por transacción
     */
    uint256 public immutable withdrawalLimit;
    
    /**
     * @notice Capacidad máxima total de ETH que puede almacenar el banco
     * @dev Variable inmutable: previene que el banco crezca sin control
     * Una vez alcanzado este límite, no se aceptan más depósitos
     * Ejemplo: Si bankCap = 100 ether, el banco no puede tener más de 100 ETH
     */
    uint256 public immutable bankCap;
    
    /**
     * @notice Depósito mínimo requerido para realizar una transacción
     * @dev Constante: usa menos gas que una variable inmutable
     * Las constantes se calculan en tiempo de compilación
     * Establecido en 0.001 ETH para evitar spam de micro-transacciones
     */
    uint256 public constant MINIMUM_DEPOSIT = 0.001 ether;
    
    
    // ============================================
    // VARIABLES DE ESTADO (STORAGE)
    // ============================================
    
    /**
     * @notice Balance total de ETH actualmente almacenado en el banco
     * @dev Se actualiza en cada depósito (+) y retiro (-)
     * Esta variable rastrea cuánto ETH hay en total en todas las bóvedas
     * Debe ser siempre <= bankCap
     */
    uint256 public totalBankBalance;
    
    /**
     * @notice Contador del número total de depósitos realizados desde el despliegue
     * @dev Útil para:
     * - Estadísticas del banco
     * - Auditoría de actividad
     * - Análisis de uso
     * Se incrementa en 1 con cada depósito exitoso
     */
    uint256 public totalDeposits;
    
    /**
     * @notice Contador del número total de retiros realizados desde el despliegue
     * @dev Similar a totalDeposits, permite rastrear la actividad de retiros
     * Se incrementa en 1 con cada retiro exitoso
     */
    uint256 public totalWithdrawals;
    
    
    // ============================================
    // MAPPINGS
    // ============================================
    
    /**
     * @notice Mapeo que almacena el balance de cada usuario en su bóveda personal
     * @dev Estructura: mapping(dirección del usuario => balance en wei)
     * 
     * Cada usuario tiene su propia "caja fuerte" independiente
     * - Key: address del usuario (dirección de Ethereum)
     * - Value: uint256 balance en wei (1 ether = 10^18 wei)
     * 
     * Ejemplo:
     * vaults[0x123...] = 5000000000000000000 (5 ETH)
     * vaults[0x456...] = 1000000000000000000 (1 ETH)
     */
    mapping(address => uint256) public vaults;
    
    
    // ============================================
    // EVENTOS
    // ============================================
    
    /**
     * @notice Emitido cuando un usuario deposita ETH exitosamente
     * @param user Dirección del usuario que realizó el depósito
     * @param amount Cantidad de ETH depositada en wei
     * @param newBalance Nuevo balance total del usuario después del depósito
     * @dev Los eventos son importantes porque:
     * - Permiten que las dApps escuchen cambios en tiempo real
     * - Se pueden indexar para búsquedas eficientes (indexed)
     * - Cuestan menos gas que almacenar en storage
     */
    event Deposit(address indexed user, uint256 amount, uint256 newBalance);
    
    /**
     * @notice Emitido cuando un usuario retira ETH exitosamente
     * @param user Dirección del usuario que realizó el retiro
     * @param amount Cantidad de ETH retirada en wei
     * @param remainingBalance Balance que le queda al usuario después del retiro
     * @dev indexed permite filtrar eventos por dirección de usuario específica
     */
    event Withdrawal(address indexed user, uint256 amount, uint256 remainingBalance);
    
    
    // ============================================
    // ERRORES PERSONALIZADOS
    // ============================================
    
    /**
     * @notice Error cuando el depósito es menor al mínimo requerido
     * @param sent Cantidad que el usuario intentó depositar
     * @param minimum Cantidad mínima requerida (MINIMUM_DEPOSIT)
     * @dev Los errores personalizados ahorran gas comparado con require con strings
     * Solidity 0.8.4+ soporta errores personalizados
     */
    error DepositTooSmall(uint256 sent, uint256 minimum);
    
    /**
     * @notice Error cuando un depósito excedería la capacidad máxima del banco
     * @param attempted Cantidad que se intentó depositar
     * @param available Espacio disponible en el banco antes de alcanzar el cap
     * @dev Protege al banco de crecer sin límite
     */
    error BankCapExceeded(uint256 attempted, uint256 available);
    
    /**
     * @notice Error cuando el usuario no tiene suficiente balance para retirar
     * @param requested Cantidad que el usuario quiere retirar
     * @param available Balance actual del usuario en su bóveda
     * @dev Previene retiros que dejarían el balance negativo
     */
    error InsufficientBalance(uint256 requested, uint256 available);
    
    /**
     * @notice Error cuando el retiro supera el límite permitido por transacción
     * @param requested Cantidad que el usuario quiere retirar
     * @param limit Límite máximo permitido (withdrawalLimit)
     * @dev Mecanismo de seguridad para prevenir drenado masivo
     */
    error WithdrawalLimitExceeded(uint256 requested, uint256 limit);
    
    /**
     * @notice Error cuando el banco no tiene suficiente ETH líquido
     * @param requested Cantidad solicitada para retirar
     * @param available ETH disponible en el contrato
     * @dev Situación poco común, pero puede ocurrir en casos extremos
     */
    error InsufficientBankLiquidity(uint256 requested, uint256 available);
    
    /**
     * @notice Error cuando falla la transferencia de ETH al usuario
     * @dev Se lanza cuando la llamada de bajo nivel (call) falla
     * Puede ocurrir si:
     * - El destinatario es un contrato sin función receive/fallback
     * - El destinatario rechaza el ETH
     * - Se agota el gas
     */
    error TransferFailed();
    
    /**
     * @notice Error cuando se intenta operar con cantidad cero
     * @dev Previene transacciones innecesarias que desperdiciarían gas
     */
    error ZeroAmount();
    
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    /**
     * @notice Inicializa el contrato con los límites del banco
     * @param _withdrawalLimit Límite máximo que se puede retirar por transacción (en wei)
     * @param _bankCap Capacidad máxima total del banco (en wei)
     * @dev El constructor se ejecuta una sola vez al desplegar el contrato
     * 
     * Validaciones:
     * - withdrawalLimit debe ser > 0
     * - bankCap debe ser > 0
     * - withdrawalLimit no puede ser mayor que bankCap
     * 
     * Ejemplo de despliegue:
     * new KipuBank(1 ether, 100 ether)
     * - Permite retiros de máximo 1 ETH por transacción
     * - Capacidad total del banco: 100 ETH
     */
    constructor(uint256 _withdrawalLimit, uint256 _bankCap) {
        require(_withdrawalLimit > 0, "Withdrawal limit must be greater than 0");
        require(_bankCap > 0, "Bank cap must be greater than 0");
        require(_withdrawalLimit <= _bankCap, "Withdrawal limit cannot exceed bank cap");
        
        withdrawalLimit = _withdrawalLimit;
        bankCap = _bankCap;
    }
    
    
    // ============================================
    // MODIFICADORES
    // ============================================
    
    /**
     * @notice Modificador que valida que una cantidad sea mayor que cero
     * @param amount Cantidad a validar
     * @dev Los modificadores permiten reutilizar lógica de validación
     * 
     * El símbolo _ (underscore) indica dónde se ejecuta el código de la función
     * 
     * Ejemplo de uso:
     * function deposit() external payable nonZeroAmount(msg.value) { ... }
     * 
     * Flujo de ejecución:
     * 1. Se ejecuta la validación del modificador
     * 2. Si pasa, se ejecuta el código de la función (donde está _)
     * 3. Si falla, revierte toda la transacción
     */
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert ZeroAmount();
        }
        _; // Aquí se ejecuta el código de la función
    }
    
    
    // ============================================
    // FUNCIONES EXTERNAS PAYABLE
    // ============================================
    
    /**
     * @notice Permite a los usuarios depositar ETH en su bóveda personal
     * @dev Función payable que acepta ETH junto con la llamada
     * 
     * PATRÓN CHECKS-EFFECTS-INTERACTIONS (CEI):
     * ==========================================
     * Este patrón es crucial para la seguridad contra ataques de reentrancia
     * 
     * 1. CHECKS: Todas las validaciones primero
     * 2. EFFECTS: Cambios en el estado del contrato
     * 3. INTERACTIONS: Llamadas externas y eventos
     * 
     * Validaciones realizadas:
     * - msg.value debe ser > 0 (modificador)
     * - msg.value debe ser >= MINIMUM_DEPOSIT
     * - El depósito no debe exceder el espacio disponible en el banco
     * 
     * Efectos:
     * - Incrementa vaults[msg.sender] con el valor depositado
     * - Incrementa totalBankBalance
     * - Incrementa totalDeposits
     * 
     * Ejemplo de uso desde web3:
     * await contract.deposit({ value: ethers.utils.parseEther("1.0") })
     */
    function deposit() external payable nonZeroAmount(msg.value) {
        // ============ CHECKS ============
        // Validación 1: Verificar depósito mínimo
        if (msg.value < MINIMUM_DEPOSIT) {
            revert DepositTooSmall(msg.value, MINIMUM_DEPOSIT);
        }  
        // Validación 2: Verificar que no se exceda la capacidad del banco
        uint256 availableSpace = bankCap - totalBankBalance;
        if (msg.value > availableSpace) {
            revert BankCapExceeded(msg.value, availableSpace);
        }    
        // ============ EFFECTS ============
        // Actualizar el estado ANTES de cualquier interacción externa
        vaults[msg.sender] += msg.value; // Incrementar bóveda del usuario
        totalBankBalance += msg.value;    // Incrementar balance total del banco
        totalDeposits++;                   // Incrementar contador de depósitos      
        // ============ INTERACTIONS ============
        // Emitir evento (considerado seguro, no es una llamada externa peligrosa)
        emit Deposit(msg.sender, msg.value, vaults[msg.sender]);
    } 
    
    // ============================================
    // FUNCIONES EXTERNAS
    // ============================================
    
    /**
     * @notice Permite a los usuarios retirar ETH de su bóveda
     * @param amount Cantidad de ETH a retirar en wei
     * @dev Función crítica que implementa múltiples capas de seguridad
     * 
     * SEGURIDAD:
     * ==========
     * 1. Sigue el patrón CEI estrictamente
     * 2. Usa call en lugar de transfer (más seguro post-Estambul)
     * 3. Actualiza el estado ANTES de enviar ETH
     * 4. Múltiples validaciones
     * 
     * Validaciones:
     * - amount debe ser > 0 (modificador)
     * - Usuario debe tener suficiente balance en su bóveda
     * - amount no debe exceder withdrawalLimit
     * - El banco debe tener suficiente liquidez
     * 
     * ¿Por qué usar call en lugar de transfer?
     * - transfer: envía 2300 gas fijo (insuficiente para contratos complejos)
     * - send: igual que transfer pero retorna bool
     * - call: flexible, envía todo el gas disponible, más seguro
     * 
     * Ejemplo:
     * await contract.withdraw(ethers.utils.parseEther("0.5"))
     */
    function withdraw(uint256 amount) external nonZeroAmount(amount) {
        // ============ CHECKS ============
        // Validación 1: Usuario tiene suficiente balance
        if (amount > vaults[msg.sender]) {
            revert InsufficientBalance(amount, vaults[msg.sender]);
        }
        
        // Validación 2: Respetar el límite de retiro por transacción
        if (amount > withdrawalLimit) {
            revert WithdrawalLimitExceeded(amount, withdrawalLimit);
        }
        
        // Validación 3: El banco tiene suficiente ETH líquido
        // address(this).balance = ETH total en el contrato
        if (amount > address(this).balance) {
            revert InsufficientBankLiquidity(amount, address(this).balance);
        }
        
        // ============ EFFECTS ============
        // Actualizar TODOS los estados ANTES de enviar ETH
        vaults[msg.sender] -= amount;      // Reducir bóveda del usuario
        totalBankBalance -= amount;        // Reducir balance total del banco
        totalWithdrawals++;                // Incrementar contador de retiros
        
        // Guardar el balance restante para el evento
        uint256 remainingBalance = vaults[msg.sender];
        
        // ============ INTERACTIONS ============
        // Enviar ETH usando call (método más seguro)
        // call retorna (bool success, bytes memory data)
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        
        // Verificar que la transferencia fue exitosa
        if (!success) {
            revert TransferFailed();
        }
        
        // Emitir evento después de la transferencia exitosa
        emit Withdrawal(msg.sender, amount, remainingBalance);
    }
    
    
    // ============================================
    // FUNCIONES DE VISTA (VIEW)
    // ============================================
    
    /**
     * @notice Obtiene información completa sobre la cuenta de un usuario
     * @param user Dirección del usuario a consultar
     * @return userBalance Balance actual del usuario en su bóveda (en wei)
     * @return maxWithdrawal Máximo que puede retirar en una transacción (en wei)
     * @return canWithdrawFully Si puede retirar todo su balance de una sola vez
     * @dev Función VIEW: no modifica el estado, solo lee
     * 
     * Las funciones view:
     * - No consumen gas cuando se llaman desde fuera de la blockchain (RPC)
     * - Consumen gas si son llamadas por otra función que modifica estado
     * - Pueden leer variables de estado pero no modificarlas
     * - Útiles para interfaces de usuario (dApps)
     * 
     * Esta función es útil para que un frontend muestre:
     * - Cuánto ETH tiene el usuario depositado
     * - Cuánto puede retirar máximo ahora
     * - Si necesitará hacer múltiples retiros para sacar todo
     * 
     * Ejemplo de uso:
     * const [balance, maxW, canWithdrawAll] = await contract.getUserInfo(userAddress)
     */
    function getUserInfo(address user) 
        external 
        view 
        returns (
            uint256 userBalance, 
            uint256 maxWithdrawal, 
            bool canWithdrawFully
        ) 
    {
        // Obtener el balance del usuario de su bóveda
        userBalance = vaults[user];
        
        // Calcular el máximo retirable usando función privada
        maxWithdrawal = _calculateMaxWithdrawal(user);
        
        // Determinar si puede retirar todo de una vez
        // Solo puede si su balance <= withdrawalLimit
        canWithdrawFully = userBalance <= withdrawalLimit;
        
        return (userBalance, maxWithdrawal, canWithdrawFully);
    }
    
    /**
     * @notice Obtiene estadísticas generales del banco
     * @return totalBalance Balance total de ETH en el banco (en wei)
     * @return depositsCount Número total de depósitos desde el despliegue
     * @return withdrawalsCount Número total de retiros desde el despliegue
     * @return remainingCapacity Espacio disponible antes de alcanzar bankCap (en wei)
     * @dev Función view útil para dashboards, análisis y monitoreo
     * 
     * Esta información es valiosa para:
     * - Mostrar estadísticas en la interfaz
     * - Análisis de uso del banco
     * - Saber si el banco está cerca del límite
     * - Auditoría de actividad
     * 
     * Ejemplo de uso en un dashboard:
     * const stats = await contract.getBankStats()
     * console.log(`Total depositado: ${ethers.utils.formatEther(stats.totalBalance)} ETH`)
     * console.log(`Operaciones totales: ${stats.depositsCount + stats.withdrawalsCount}`)
     */
    function getBankStats() 
        external 
        view 
        returns (
            uint256 totalBalance,
            uint256 depositsCount,
            uint256 withdrawalsCount,
            uint256 remainingCapacity
        )
    {
        totalBalance = totalBankBalance;
        depositsCount = totalDeposits;
        withdrawalsCount = totalWithdrawals;
        
        // Calcular espacio disponible
        remainingCapacity = bankCap - totalBankBalance;
        
        return (totalBalance, depositsCount, withdrawalsCount, remainingCapacity);
    }
    
    // ============================================
    // FUNCIONES PRIVADAS
    // ============================================
    
    /**
     * @notice Calcula el máximo que un usuario puede retirar considerando todos los límites
     * @param user Dirección del usuario
     * @return Cantidad máxima retirable en wei
     * @dev Función PRIVADA: solo accesible desde dentro de este contrato
     * 
     * ¿Por qué PRIVATE y no INTERNAL?
     * - private: solo este contrato puede llamarla
     * - internal: este contrato Y contratos herederos pueden llamarla
     * - external: solo llamadas externas
     * - public: desde cualquier lugar
     * 
     * Esta función considera TRES factores:
     * 1. Balance del usuario en su bóveda
     * 2. Límite de retiro por transacción (withdrawalLimit)
     * 3. Liquidez actual del banco (ETH disponible en el contrato)
     * 
     * Retorna el MENOR de estos tres valores
     * 
     * Ejemplo:
     * - Usuario tiene 10 ETH
     * - withdrawalLimit = 1 ETH
     * - Banco tiene 5 ETH
     * → Retorna: 1 ETH (el menor)
     * 
     * Caso extremo:
     * - Usuario tiene 0.5 ETH
     * - withdrawalLimit = 1 ETH
     * - Banco tiene 100 ETH
     * → Retorna: 0.5 ETH (todo el balance del usuario)
     */
    function _calculateMaxWithdrawal(address user) private view returns (uint256) {
        // Factor 1: Balance del usuario
        uint256 userBalance = vaults[user];
        
        // Factor 2: Liquidez del banco
        // address(this).balance = ETH total en el contrato
        uint256 bankLiquidity = address(this).balance;
        
        // Empezar con el balance del usuario como máximo inicial
        uint256 maxAmount = userBalance;
        
        // Aplicar límite de retiro por transacción
        if (maxAmount > withdrawalLimit) {
            maxAmount = withdrawalLimit;
        }
        
        // Aplicar límite de liquidez del banco
        if (maxAmount > bankLiquidity) {
            maxAmount = bankLiquidity;
        }
        
        return maxAmount;
    }
    
    
    // ============================================
    // FUNCIÓN RECEIVE
    // ============================================
    
    /**
     * @notice Función especial que recibe ETH enviado directamente al contrato
     * @dev receive() se ejecuta cuando:
     * - Se envía ETH al contrato SIN datos (msg.data está vacío)
     * - No se llama a ninguna función específica
     * 
     * Diferencia entre receive() y fallback():
     * - receive(): solo para recibir ETH puro, sin datos
     * - fallback(): se ejecuta cuando se llama a una función inexistente O con datos
     * 
     * Esta implementación trata el envío directo de ETH como un depósito
     * Aplica las mismas validaciones que la función deposit()
     * 
     * Ejemplo de uso:
     * // Desde ethers.js
     * await signer.sendTransaction({
     *   to: contractAddress,
     *   value: ethers.utils.parseEther("1.0")
     * })
     * 
     * // Desde web3.js
     * await web3.eth.sendTransaction({
     *   from: account,
     *   to: contractAddress,
     *   value: web3.utils.toWei("1", "ether")
     * })
     */
    receive() external payable {
        // Validación 1: No permitir envíos de 0 ETH
        if (msg.value == 0) {
            revert ZeroAmount();
        }
        
        // Validación 2: Verificar depósito mínimo
        if (msg.value < MINIMUM_DEPOSIT) {
            revert DepositTooSmall(msg.value, MINIMUM_DEPOSIT);
        }
        
        // Validación 3: Verificar capacidad del banco
        uint256 availableSpace = bankCap - totalBankBalance;
        if (msg.value > availableSpace) {
            revert BankCapExceeded(msg.value, availableSpace);
        }
        
        // Actualizar el estado (patrón CEI)
        vaults[msg.sender] += msg.value;
        totalBankBalance += msg.value;
        totalDeposits++;
        
        // Emitir evento
        emit Deposit(msg.sender, msg.value, vaults[msg.sender]);
    }
}