<h1>descripción del kipubank</h1>
KipuBank es un contrato inteligente de banco descentralizado que permite a los usuarios depositar y retirar ETH de forma segura. Cada usuario tiene su propia bóveda personal donde se almacenan sus fondos. El contrato implementa el patrón CEI (Checks-Effects-Interactions) para prevenir ataques de reentrada y utiliza errores personalizados para optimizar el uso de gas. Los límites están configurados directamente en el código: capacidad máxima del banco de 100 ETH, límite de retiro de 1 ETH por transacción, y depósito mínimo de 0.001 ETH.

<h1>Instricciones de despliegue</h1>
-Abre Remix IDE en https://remix.ethereum.org/ <hr>
-Crea un nuevo archivo en la carpeta "contracts" llamado KipuBank.sol <hr>
-Copia y pega el código del contrato <hr>
-Ve a la pestaña "Solidity Compiler" y selecciona la versión 0.8.26 <hr>
-Click en "Compile KipuBank.sol" <hr>
-Ve a la pestaña "Deploy & Run Transactions" <hr>
-Selecciona el environment <hr>
Click en "Deploy" 

<h1>Como interactuar con el contrato</h1>
<h2>Depositar ETH</h2>
-En Remix, localiza el campo "VALUE" encima de los botones de funciones <hr>
-Escribe la cantidad a depositar (ejemplo: 0.01) <hr>
-En el dropdown al lado, selecciona "ether" <hr>
-Click en el botón rojo "deposit" <hr>
-Confirma la transacción en MetaMask 

<h2>Retirar ETH</h2>
-Click en la función "withdraw" <hr>
-Ingresa la cantidad en WEI que deseas retirar <hr>
-Click en "transact" <hr>
-Confirma la transacción 
