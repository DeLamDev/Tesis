// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DEX {
    address public admin;

    struct Orden {
        address trader;
        address tokenComprado;
        address tokenPagado;
        uint256 numerador;
        uint256 denominador;
        uint256 cantidad;
    }

    mapping(address => mapping(address => uint256)) public balances;
    mapping(address => Orden[]) public ordenes;

    constructor() {
        admin = msg.sender;
    }

    modifier controlAdmin() {
        require(msg.sender == admin, "Solo el admin puede llamar esta funcion.");
        _;
    }

    function deposito(address token, uint256 cantidad) external {
        require(cantidad > 0, "La cantidad debe ser superior a cero.");
        require(IERC20(token).transferFrom(msg.sender, address(this), cantidad), "Transaccion fallida.");
        balances[msg.sender][token] += cantidad;
    }

    function retiro(address token, uint256 cantidad) external {
        require(cantidad > 0, "La cantidad debe ser superior a cero.");
        require(balances[msg.sender][token] >= cantidad, "Fondos insuficientes.");
        balances[msg.sender][token] -= cantidad;
        require(IERC20(token).transfer(msg.sender, cantidad), "Transaccion fallida.");
    }

    function solicitarOrden(
        address tokenComprado,
        address tokenPagado,
        uint256 numerador,
        uint256 denominador,
        uint256 cantidad
    ) external {
        require(numerador > 0 && denominador > 0, "El precio debe ser superior a cero.");
        require(balances[msg.sender][tokenPagado] >= cantidad, "Fondos insuficientes.");

        Orden memory nuevaOrden = Orden(msg.sender, tokenComprado, tokenPagado, numerador, denominador, cantidad);
        ordenes[tokenComprado].push(nuevaOrden);
    }

    function ejecutarTrades(address tokenComprado, address tokenPagado) external {
        uint256 indiceCompra = 0;
        uint256 indiceVenta = 0;
    
        while (indiceCompra < ordenes[tokenComprado].length && indiceVenta < ordenes[tokenPagado].length) {
            Orden storage ordenCompra = ordenes[tokenComprado][indiceCompra];
            Orden storage ordenVenta = ordenes[tokenPagado][indiceVenta];

            // Calculo de equivalencia en los tipos de cambio
            uint256 precio = (ordenCompra.numerador * ordenVenta.numerador * 10**18) / (ordenCompra.denominador * ordenVenta.denominador);

            // Verificacion de que encuadran los precios y las cantidades
            if (calculo_rango_precios(precio) && calculo_equi_cantidades(ordenCompra, ordenVenta)) {
                // Calculo de las expectivas de compra y venta
                uint256 cantidadCompra = ordenVenta.cantidad;
                uint256 cantidadVenta = ordenVenta.cantidad * ordenVenta.denominador / ordenVenta.numerador;

                // Ejecucion del trade
                balances[ordenCompra.trader][ordenCompra.tokenComprado] += cantidadCompra;
                balances[ordenCompra.trader][ordenCompra.tokenPagado] -= cantidadVenta;
                balances[ordenVenta.trader][ordenVenta.tokenComprado] += cantidadVenta;
                balances[ordenVenta.trader][ordenVenta.tokenPagado] -= cantidadCompra;

                // Actualizar cantidades ordenes
                ordenCompra.cantidad -= cantidadVenta;
                ordenVenta.cantidad -= cantidadCompra;

                // Checar si hubo una ejecucion total o parcial del trade
                if (ordenCompra.cantidad == 0) {
                    indiceCompra++;
                }
                else if (ordenVenta.cantidad == 0) {
                        indiceVenta++;
                    }
                else {
                    indiceVenta++;
                }
            } else {
                indiceVenta++;
            }
        }

        // Limpieza de ordenes
        limpiarOrdenesParciales(ordenes[tokenComprado]);
        limpiarOrdenesParciales(ordenes[tokenPagado]);
    }

    // Margen del 5% en el amparejamiento de ordenes
    function calculo_rango_precios(uint256 precio) internal pure returns (bool) {
        return (precio >= 950000000000000000 && precio <= 1050000000000000000);
    }

    // Las equivalencias en las cantidades se hacen con base en la demanda
    function calculo_equi_cantidades(Orden memory compra, Orden memory venta) internal pure returns (bool) {
        uint256 cantidadComprada = compra.cantidad * compra.denominador / compra.numerador;
        uint256 cantidadVendida = venta.cantidad * venta.denominador / venta.numerador;
        return cantidadComprada >= venta.cantidad && cantidadVendida <=  compra.cantidad;
    }

    // Se limpian las ordenes staisfechas y se reorganizan las parciales, poniendo las ultimas al inicio
    function limpiarOrdenesParciales(Orden[] storage ordenes) internal {
        uint256 i = 0;
        while (i < ordenes.length) {
            if (ordenes[i].cantidad == 0) {
                if (i < ordenes.length - 1) {
                    ordenes[i] = ordenes[ordenes.length - 1];
                }
                ordenes.pop();
            } else {
                i++;
            }
        }
    }
}
