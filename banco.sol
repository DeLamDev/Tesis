// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract banco {
    address tokenAddress;
    IERC20 token;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public erc20Balances;
    mapping(uint256 => Prestamo) public solicitudes;
    mapping(uint256 => Prestamo) public tokenSolicitudes;
    address admin;
    uint256 idETH;
    uint256 idToken;
    uint256 ganancia;
    enum estatusPrestamo { Pendiente, Aprobado, Dispuesto, Pagado }
    uint256 segundos =  31536000;


    struct Prestamo {
        address deudor;
        uint256 cantidadTotal;
        uint256 cantidad;
        uint8 tasaInteres;
        uint8 termino; 
        uint256 fechaInicio;
        uint256 fechaTermino;
        estatusPrestamo estatus;
        bool estoken;
    }
    
    event PrestamoSolicitado(uint256 indexed id_prestamo, address indexed deudor, uint256 cantidad, bool estoken);
    event PrestamoAprobado(uint256 indexed id_prestamo, address indexed deudor, bool estoken);
    event PrestamoRevertido(uint256 indexed id_prestamo, address indexed deudor, bool estoken);
    event PrestamoPagado(uint256 indexed id_prestamo, uint256 cantidad, bool liquidado, bool estoken);
    event DepositoRecibido(address indexed depositante, uint256 cantidad, bool estoken);
    event DepositoRetirado(address indexed  depositante, uint256 cantidad, bool estoken);

    modifier controlAdmin() {
        require(msg.sender == admin, "Solo el admin puede ejecutar esta funcion.");
        _;
    }


    constructor(address _tokenAddress) {
        tokenAddress = _tokenAddress;
        token = IERC20(tokenAddress);
        admin = msg.sender;
        idETH = 0;
        idToken = 0;
    }

    function liquidezTotalEth() public view returns (uint256) {
        return address(this).balance;
    }

    function liquidezToken() public view returns (uint256) {
        return token.balanceOf(address(this)); 
    }

    function calcularFechas(uint256 tiempo) private view returns (uint256 fechaInicio, uint256 fechaFin) {
        uint256 fin = block.timestamp + (segundos * tiempo);
        return (block.timestamp, fin);
    }

    function deposito_eth() external  payable {
        require(msg.value > 0, "La cantidad debe ser mayor a cero.");
        balances[msg.sender] += msg.value;
        emit DepositoRecibido(msg.sender, msg.value, false);
    }
    
    function retiro_eth(uint256 cantidad) external {
        require(cantidad > 0, "La cantidad debe ser mayor a cero.");
        require(balances[msg.sender] >= cantidad, "Fondos insuficientes");

        balances[msg.sender] -= cantidad;
        payable(msg.sender).transfer(cantidad);
        emit DepositoRetirado(msg.sender, cantidad, false);
    }

    function depositar_token(uint256 cantidad) external {
        require(cantidad > 0, "La cantidad debe ser mayor a cero.");
        require(token.balanceOf(msg.sender) >= cantidad, "Fondos insuficientes.");
        token.transferFrom(msg.sender, address(this), cantidad);
        erc20Balances[msg.sender] += cantidad;
        emit DepositoRecibido(msg.sender, cantidad, true);
    }

    function retiro_token(uint256 cantidad) external {
        require(cantidad > 0, "La cantidad debe ser mayor a cero.");
        require(cantidad <= erc20Balances[msg.sender], "Fondos insuficientes");
        erc20Balances[msg.sender] -= cantidad;
        token.transfer(msg.sender, cantidad);
        emit DepositoRetirado(msg.sender, cantidad, true);
    }

    function solicitudPrestamoDiscrecional(uint256 cantidad, uint8 termino, uint8 interes, bool estoken) external {
        require(interes > 0, "Interes no puede ser cero.");
        require(termino > 0, "Termino no puede ser cero.");
        uint256 prestamoTotal = cantidad + cantidad * interes * termino / 100;

        Prestamo storage nuevoPrestamo = estoken ? tokenSolicitudes[idToken] : solicitudes[idETH];
        nuevoPrestamo.deudor = msg.sender;
        nuevoPrestamo.cantidadTotal = prestamoTotal;
        nuevoPrestamo.cantidad = cantidad;
        nuevoPrestamo.tasaInteres = interes;
        nuevoPrestamo.termino = termino;
        nuevoPrestamo.estatus = estatusPrestamo.Pendiente;
        nuevoPrestamo.estoken = estoken;

        estoken ? idToken++ : idETH++;

        emit PrestamoSolicitado(estoken ? idToken : idETH, msg.sender, cantidad, estoken);
    }

    function autorizarPrestamo(uint256 id, bool estoken) external controlAdmin {
        estoken ? tokenSolicitudes[id].estatus = estatusPrestamo.Aprobado : solicitudes[id].estatus = estatusPrestamo.Aprobado;
        emit PrestamoAprobado(id, estoken ? tokenSolicitudes[id].deudor : solicitudes[id].deudor, estoken);
    }

    function revertirAutorizacion(uint256 id, bool estoken) external controlAdmin {
        estoken ? tokenSolicitudes[id].estatus = estatusPrestamo.Pendiente : solicitudes[id].estatus = estatusPrestamo.Pendiente;
        emit PrestamoRevertido(id, estoken ? tokenSolicitudes[id].deudor : solicitudes[id].deudor, estoken);
    }

    function obtenerPrestamoETH(uint256 id) external {
        uint256 capitalizacionMaxima = address(this).balance * 9 / 10;
        require(solicitudes[id].cantidad <= capitalizacionMaxima, "Prestamo excede la capitalizacion.");
        require(msg.sender == solicitudes[id].deudor, "Solo el deudor puede obtener el prestamo.");
        require(solicitudes[id].estatus == estatusPrestamo.Aprobado, "El prestamo no ha sido aprobado.");
        solicitudes[id].estatus = estatusPrestamo.Dispuesto;
        (solicitudes[id].fechaInicio, solicitudes[id].fechaTermino) = calcularFechas(solicitudes[id].termino);
        payable(msg.sender).transfer(solicitudes[id].cantidad);
    }

    function pagarDeudaETH(uint256 id) external payable {
        require(solicitudes[id].estatus == estatusPrestamo.Dispuesto, "Prestamo no ha sido dispuesto.");
        require(msg.value > 0, "Monto a pagar debe ser mayor a cero.");
        require(msg.sender == solicitudes[id].deudor, "Solo el deudor puede pagar su deuda.");
        require(msg.value <= solicitudes[id].cantidadTotal, "Monto a pagar debe ser igual o menor al credito solicitado.");
        solicitudes[id].cantidadTotal -= msg.value;
        if(solicitudes[id].cantidadTotal == 0) {
            solicitudes[id].estatus = estatusPrestamo.Pagado;
            ganancia += solicitudes[id].cantidad * solicitudes[id].tasaInteres / 100;
            balances[admin] += ganancia;
            emit PrestamoPagado(id, msg.value, true, false);
        } else {
            emit PrestamoPagado(id, msg.value, false, false);
        }
    }

    function obtenerPrestamoToken(uint256 id) external {
        uint256 capitalizacionMaxima = token.balanceOf(address(this)) * 9 / 10;
        require(tokenSolicitudes[id].cantidad <= capitalizacionMaxima, "Prestamo excede la capitalizacion.");
        require(msg.sender == tokenSolicitudes[id].deudor, "Solo el deudor puede obtener el prestamo.");
        require(tokenSolicitudes[id].estatus == estatusPrestamo.Aprobado, "El prestamo no ha sido aprobado.");
        tokenSolicitudes[id].estatus = estatusPrestamo.Dispuesto;
        (tokenSolicitudes[id].fechaInicio, tokenSolicitudes[id].fechaTermino) = calcularFechas(tokenSolicitudes[id].termino);
        token.transfer(msg.sender, tokenSolicitudes[id].cantidad);
    }

    function pagarDeudaToken(uint256 id, uint256 cantidad) external {
        require(tokenSolicitudes[id].estatus == estatusPrestamo.Dispuesto, "Prestamo no ha sido dispuesto.");
        require(msg.sender == tokenSolicitudes[id].deudor, "Solo el deudor puede pagar su deuda.");
        require(cantidad <= tokenSolicitudes[id].cantidadTotal, "Monto a pagar debe ser igual o menor a la deuda total.");

        tokenSolicitudes[id].cantidadTotal -= cantidad;
        if (tokenSolicitudes[id].cantidadTotal == 0) {
            tokenSolicitudes[id].estatus = estatusPrestamo.Pagado;
            ganancia += tokenSolicitudes[id].cantidad * tokenSolicitudes[id].tasaInteres / 100;
            erc20Balances[admin] += ganancia;
            emit PrestamoPagado(id, cantidad, true, true);
        } else {
            emit PrestamoPagado(id, cantidad, false, true);
        }

        require(token.transferFrom(msg.sender, address(this), cantidad), "Transferencia de tokens fallida");
    }


}
