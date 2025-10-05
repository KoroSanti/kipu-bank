// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*
 * @title KipuBank
 * @author Rodriguez Santiago
 * @notice Banco descentralizado que permite depositar y retirar ETH con seguridad
 * @Date 03/10/25
 */
contract KipuBank {
    
    // VARIABLES INMUTABLES Y CONSTANTES
    
    /**
     * @notice Límite máximo que un usuario puede retirar en una sola transacción
     */
    uint256 public immutable withdrawalLimit;
    
    /**
     * @notice Capacidad máxima total de ETH que puede almacenar el banco
     */
    uint256 public immutable bankCap;
    
    /**
     * @notice Depósito mínimo requerido para realizar una transacción
     */
    uint256 public constant MINIMUM_DEPOSIT = 0.001 ether;
    
    
    // VARIABLES DE ESTADO
    
    /**
     * @notice Balance total de ETH actualmente almacenado en el banco
     */
    uint256 public totalBankBalance;
    
    /**
     * @notice Contador del número total de depósitos realizados desde el despliegue
     */
    uint256 public totalDeposits;
    
    /**
     * @notice Contador del número total de retiros realizados desde el despliegue
     */
    uint256 public totalWithdrawals;
    

    // MAPPINGS
    
    /**
     * @notice Mapeo que almacena el balance de cada usuario en su bóveda personal
     */
    mapping(address => uint256) public vaults;
    
    
    // EVENTOS
    
    /**
     * @notice Emitido cuando un usuario deposita ETH exitosamente
     */
    event Deposit(address indexed user, uint256 amount, uint256 newBalance);
    
    /**
     * @notice Emitido cuando un usuario retira ETH exitosamente
     */
    event Withdrawal(address indexed user, uint256 amount, uint256 remainingBalance);
    
    
    // ERRORES PERSONALIZADOS
    
    /**
     * @notice Error cuando el depósito es menor al mínimo requerido
     */
    error DepositTooSmall(uint256 sent, uint256 minimum);
    
    /**
     * @notice Error cuando un depósito excedería la capacidad máxima del banco
     */
    error BankCapExceeded(uint256 attempted, uint256 available);
    
    /**
     * @notice Error cuando el usuario no tiene suficiente balance para retirar
     */
    error InsufficientBalance(uint256 requested, uint256 available);
    
    /**
     * @notice Error cuando el retiro supera el límite permitido por transacción
     */
    error WithdrawalLimitExceeded(uint256 requested, uint256 limit);
    
    /**
     * @notice Error cuando el banco no tiene suficiente ETH líquido
     */
    error InsufficientBankLiquidity(uint256 requested, uint256 available);
    
    /**
     * @notice Error cuando falla la transferencia de ETH al usuario
     */
    error TransferFailed();
    
    /**
     * @notice Error cuando se intenta operar con cantidad cero
     */
    error ZeroAmount();
    
    // CONSTRUCTOR
    
    /**
     * @notice Inicializa el contrato con los límites del banco predefinidos
     */
    constructor() {
        withdrawalLimit = 1 ether;
        bankCap = 100 ether;
    }
    
    
    // MODIFICADORES
    
    /**
     * @notice Modificador que valida que una cantidad sea mayor que cero
     */

    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert ZeroAmount();
        }
        _;
    }
    
    // FUNCIONES EXTERNAS PAYABLE
    
    /**
     * @notice Permite a los usuarios depositar ETH en su bóveda personal
     */
    function deposit() external payable nonZeroAmount(msg.value) {
    
        // Validación 1: Verificar depósito 
        
        if (msg.value < MINIMUM_DEPOSIT) {
            revert DepositTooSmall(msg.value, MINIMUM_DEPOSIT);
        }  
        // Validación 2: Verificar que no se exceda la capacidad del banco

        uint256 availableSpace = bankCap - totalBankBalance;
        if (msg.value > availableSpace) {
            revert BankCapExceeded(msg.value, availableSpace);
        }    
        // Actualizar el estado ANTES de cualquier interacción externa

        vaults[msg.sender] += msg.value; 
        totalBankBalance += msg.value;    
        totalDeposits++;                         

        // Emitir evento

        emit Deposit(msg.sender, msg.value, vaults[msg.sender]);
    } 
    

    // FUNCIONES EXTERNAS
    
    /**
     * @notice Permite a los usuarios retirar ETH de su bóveda
     */
    function withdraw(uint256 amount) external nonZeroAmount(amount) {
      
        // Validación 1: Usuario tiene suficiente balance

        if (amount > vaults[msg.sender]) {
            revert InsufficientBalance(amount, vaults[msg.sender]);
        }
        
        // Validación 2: Respetar el límite de retiro por transacción

        if (amount > withdrawalLimit) {
            revert WithdrawalLimitExceeded(amount, withdrawalLimit);
        }
        
        // Validación 3: El banco tiene suficiente ETH líquido
    
        if (amount > address(this).balance) {
            revert InsufficientBankLiquidity(amount, address(this).balance);
        }
        

        // Actualizar TODOS los estados ANTES de enviar ETH

        vaults[msg.sender] -= amount;
        totalBankBalance -= amount;        
        totalWithdrawals++;               
        
        // Guardar el balance restante para el evento

        uint256 remainingBalance = vaults[msg.sender];
        
        // Enviar ETH usando call (método más seguro)
    
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        
        // Verificar que la transferencia fue exitosa

        if (!success) {
            revert TransferFailed();
        }
        
        // Emitir evento después de la transferencia exitosa

        emit Withdrawal(msg.sender, amount, remainingBalance);
    }
    
    
  
    // FUNCIONES DE VISTA (VIEW)
    
    /**
     * @notice Obtiene información completa sobre la cuenta de un usuario
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
   
        canWithdrawFully = userBalance <= withdrawalLimit;
        
        return (userBalance, maxWithdrawal, canWithdrawFully);
    }
    
    /**
     * @notice Obtiene estadísticas generales del banco

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
    

    // FUNCIONES PRIVADAS
  
    
    /**
     * @notice Calcula el máximo que un usuario puede retirar considerando todos los límites

     */
    function _calculateMaxWithdrawal(address user) private view returns (uint256) {
        // Factor 1: Balance del usuario

        uint256 userBalance = vaults[user];
        
        // Factor 2: Liquidez del banco

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
    
    
    // FUNCIÓN RECEIVE
 
    
    /**
     * @notice Función especial que recibe ETH enviado directamente al contrato

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